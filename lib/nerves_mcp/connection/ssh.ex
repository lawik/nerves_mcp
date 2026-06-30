defmodule NervesMCP.Connection.SSH do
  @moduledoc """
  Handles SSH connection to a Nerves device.

  Uses a Port to maintain an interactive SSH session and evaluate Elixir code.
  Automatically reconnects if the SSH connection drops (e.g. device reboot).
  """

  use GenServer

  require Logger

  @initial_retry_delay 1_000
  @max_retry_delay 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def eval(code, timeout \\ 15000) do
    GenServer.call(__MODULE__, {:eval, code, timeout}, timeout + 1000)
  end

  def eval_output(code, timeout \\ 15000) do
    GenServer.call(__MODULE__, {:eval_output, code, timeout}, timeout + 1000)
  end

  @doc "Run a raw shell command (no Elixir wrapping). Used in degraded shell mode."
  def shell_eval(command, timeout \\ 15000) do
    GenServer.call(__MODULE__, {:shell_eval, command, timeout}, timeout + 1000)
  end

  @doc "Run a raw shell command and capture stdout/stderr plus exit code."
  def shell_eval_output(command, timeout \\ 15000) do
    GenServer.call(__MODULE__, {:shell_eval_output, command, timeout}, timeout + 1000)
  end

  @doc """
  Probe what is on the other end. Returns:

    * `{:ok, result}` — an Elixir result came back (classify it upstream)
    * `:noise`        — bytes came back but no valid Elixir result
    * `:down`         — not connected / nothing came back
    * `:busy`         — an evaluation is already in flight
  """
  def probe(timeout \\ 4_000) do
    GenServer.call(__MODULE__, {:probe, timeout}, timeout + 1000)
  end

  def attach_console(pid \\ self()) do
    GenServer.call(__MODULE__, {:attach_console, pid})
  end

  def detach_console do
    GenServer.call(__MODULE__, :detach_console)
  end

  def send_raw(data) do
    GenServer.cast(__MODULE__, {:send_raw, data})
  end

  def reconnect do
    GenServer.call(__MODULE__, :reconnect, 10_000)
  end

  @impl true
  def init(_opts) do
    state = %{
      port: nil,
      buffer: "",
      waiting: nil,
      match_style: :elixir,
      console: nil,
      retry_delay: @initial_retry_delay
    }

    {:ok, connect(state)}
  end

  defp connect(state) do
    config = Application.get_env(:nerves_mcp, :connection, [])

    host = Keyword.fetch!(config, :host)
    user = Keyword.get(config, :user, "root")
    port = Keyword.get(config, :port, 22)
    pass = Keyword.get(config, :pass)

    ssh_args = [
      "-o",
      "StrictHostKeyChecking=no",
      "-o",
      "UserKnownHostsFile=/dev/null",
      "-o",
      "ServerAliveInterval=60",
      "-p",
      "#{port}",
      "-tt",
      "#{user}@#{host}"
    ]

    {executable, args} =
      case pass do
        nil ->
          {System.find_executable("ssh"), ssh_args}

        password when is_binary(password) ->
          case System.find_executable("sshpass") do
            nil ->
              raise "sshpass executable not found in PATH but --pass was provided"

            sshpass ->
              {sshpass, ["-p", password, "ssh" | ssh_args]}
          end
      end

    try do
      port_ref =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          args: args
        ])

      Logger.info("SSH connection started to #{user}@#{host}:#{port}")
      %{state | port: port_ref, retry_delay: @initial_retry_delay}
    rescue
      e ->
        Logger.error("Failed to start SSH connection: #{inspect(e)}")
        schedule_reconnect(state)
        %{state | port: nil}
    end
  end

  defp schedule_reconnect(state) do
    Logger.info("Scheduling SSH reconnection in #{state.retry_delay}ms")
    Process.send_after(self(), :reconnect, state.retry_delay)
  end

  defp next_retry_delay(current) do
    min(current * 2, @max_retry_delay)
  end

  @impl true
  def handle_call({:attach_console, pid}, _from, state) do
    ref = Process.monitor(pid)
    {:reply, :ok, %{state | console: {pid, ref}}}
  end

  def handle_call(:detach_console, _from, %{console: {_pid, ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:reply, :ok, %{state | console: nil}}
  end

  def handle_call(:detach_console, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(:reconnect, _from, %{port: nil} = state) do
    new_state = connect(state)
    {:reply, if(new_state.port, do: :ok, else: {:error, "reconnect failed"}), new_state}
  end

  def handle_call(:reconnect, _from, state) do
    # Close existing port and reconnect
    Port.close(state.port)
    new_state = connect(%{state | port: nil})
    {:reply, if(new_state.port, do: :ok, else: {:error, "reconnect failed"}), new_state}
  end

  @impl true
  def handle_call({:eval, _code, _timeout}, _from, %{port: nil} = state) do
    {:reply, {:error, "Device not connected (reconnecting...)"}, state}
  end

  def handle_call({:eval, code, timeout}, from, state) do
    marker = generate_marker()

    wrapped_code = """
    (fn ->
      result = try do
        {value, _binding} = Code.eval_string(#{inspect(code)})
        {:ok, inspect(value, pretty: true, limit: :infinity)}
      rescue
        e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
      catch
        kind, reason -> {:error, Exception.format(kind, reason, __STACKTRACE__)}
      end
      IO.puts("#{marker}_START")
      case result do
        {:ok, output} -> IO.puts(output)
        {:error, msg} -> IO.puts("ERROR: " <> msg)
      end
      IO.puts("#{marker}_END")
      :ok
    end).()
    """

    Port.command(state.port, wrapped_code <> "\n\n")

    timer_ref = Process.send_after(self(), {:timeout, from}, timeout)

    {:noreply, %{state | waiting: {from, marker, timer_ref, ""}, match_style: :elixir}}
  end

  def handle_call({:eval_output, _code, _timeout}, _from, %{port: nil} = state) do
    {:reply, {:error, "Device not connected (reconnecting...)"}, state}
  end

  def handle_call({:eval_output, code, timeout}, from, state) do
    marker = generate_marker()

    # Wrap code to capture IO output using StringIO
    wrapped_code = """
    (fn ->
      {:ok, capture_pid} = StringIO.open("")
      old_gl = Process.group_leader()
      Process.group_leader(self(), capture_pid)

      {output, result} = try do
        {value, _binding} = Code.eval_string(#{inspect(code)})
        Process.group_leader(self(), old_gl)
        {_, captured} = StringIO.contents(capture_pid)
        {captured, {:ok, inspect(value, pretty: true, limit: :infinity)}}
      rescue
        e ->
          Process.group_leader(self(), old_gl)
          {_, captured} = StringIO.contents(capture_pid)
          {captured, {:error, Exception.format(:error, e, __STACKTRACE__)}}
      catch
        kind, reason ->
          Process.group_leader(self(), old_gl)
          {_, captured} = StringIO.contents(capture_pid)
          {captured, {:error, Exception.format(kind, reason, __STACKTRACE__)}}
      end

      StringIO.close(capture_pid)

      IO.puts("#{marker}_START")
      IO.puts("OUTPUT:")
      IO.write(output)
      IO.puts("RESULT:")
      case result do
        {:ok, val} -> IO.puts(val)
        {:error, msg} -> IO.puts("ERROR: " <> msg)
      end
      IO.puts("#{marker}_END")
      :ok
    end).()
    """

    Port.command(state.port, wrapped_code <> "\n\n")

    timer_ref = Process.send_after(self(), {:timeout, from}, timeout)

    {:noreply, %{state | waiting: {from, marker, timer_ref, ""}, match_style: :elixir}}
  end

  def handle_call({:shell_eval, _command, _timeout}, _from, %{port: nil} = state) do
    {:reply, {:error, "Device not connected (reconnecting...)"}, state}
  end

  def handle_call({:shell_eval, command, timeout}, from, state) do
    marker = generate_marker()
    wrapped = "echo '#{marker}_START'\n#{command}\necho '#{marker}_END'\n"

    Port.command(state.port, wrapped)

    timer_ref = Process.send_after(self(), {:timeout, from}, timeout)

    {:noreply, %{state | waiting: {from, marker, timer_ref, ""}, match_style: :shell}}
  end

  def handle_call({:shell_eval_output, _command, _timeout}, _from, %{port: nil} = state) do
    {:reply, {:error, "Device not connected (reconnecting...)"}, state}
  end

  def handle_call({:shell_eval_output, command, timeout}, from, state) do
    marker = generate_marker()

    wrapped =
      "echo '#{marker}_START'\n" <>
        "echo 'OUTPUT:'\n" <>
        "#{command} 2>&1\n" <>
        "__mcp_rc=$?\n" <>
        "echo 'RESULT:'\n" <>
        "echo \"Exit code: $__mcp_rc\"\n" <>
        "echo '#{marker}_END'\n"

    Port.command(state.port, wrapped)

    timer_ref = Process.send_after(self(), {:timeout, from}, timeout)

    {:noreply, %{state | waiting: {from, marker, timer_ref, ""}, match_style: :shell}}
  end

  def handle_call({:probe, _timeout}, _from, %{port: nil} = state) do
    {:reply, :down, state}
  end

  def handle_call({:probe, _timeout}, _from, %{waiting: waiting} = state)
      when not is_nil(waiting) do
    {:reply, :busy, state}
  end

  def handle_call({:probe, timeout}, from, state) do
    marker = generate_marker()
    code = ~s|Nerves.Runtime.KV.get_active("nerves_fw_uuid")|

    wrapped_code = """
    (fn ->
      result = try do
        {value, _binding} = Code.eval_string(#{inspect(code)})
        {:ok, inspect(value, pretty: true, limit: :infinity)}
      rescue
        e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
      catch
        kind, reason -> {:error, Exception.format(kind, reason, __STACKTRACE__)}
      end
      IO.puts("#{marker}_START")
      case result do
        {:ok, output} -> IO.puts(output)
        {:error, msg} -> IO.puts("ERROR: " <> msg)
      end
      IO.puts("#{marker}_END")
      :ok
    end).()
    """

    Port.command(state.port, wrapped_code <> "\n\n")

    timer_ref = Process.send_after(self(), {:probe_timeout, from}, timeout)

    {:noreply, %{state | waiting: {from, marker, timer_ref, ""}, match_style: :elixir}}
  end

  @impl true
  def handle_cast({:send_raw, _data}, %{port: nil} = state) do
    {:noreply, state}
  end

  def handle_cast({:send_raw, data}, state) do
    Port.command(state.port, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port, waiting: nil, console: nil} = state) do
    NervesMCP.History.push(data)
    {:noreply, state}
  end

  def handle_info(
        {port, {:data, data}},
        %{port: port, waiting: nil, console: {pid, _ref}} = state
      ) do
    NervesMCP.History.push(data)
    send(pid, {:console_data, data})
    {:noreply, state}
  end

  def handle_info(
        {port, {:data, data}},
        %{port: port, waiting: {from, marker, timer_ref, acc}} = state
      ) do
    NervesMCP.History.push(data)
    new_acc = acc <> data

    case match_markers(new_acc, marker, state.match_style) do
      {:done, result} ->
        Process.cancel_timer(timer_ref)
        GenServer.reply(from, {:ok, result})
        {:noreply, %{state | waiting: nil}}

      {:cont, acc2} ->
        {:noreply, %{state | waiting: {from, marker, timer_ref, acc2}}}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("SSH process exited with status: #{status}")

    if state.waiting do
      {from, _marker, timer_ref, _acc} = state.waiting
      Process.cancel_timer(timer_ref)
      GenServer.reply(from, {:error, "SSH connection closed unexpectedly"})
    end

    # Notify console of disconnection
    if state.console do
      {pid, _ref} = state.console
      send(pid, {:console_data, "\r\n--- SSH connection lost, reconnecting... ---\r\n"})
    end

    new_state = %{
      state
      | port: nil,
        waiting: nil,
        retry_delay: next_retry_delay(state.retry_delay)
    }

    schedule_reconnect(new_state)
    {:noreply, new_state}
  end

  def handle_info(:reconnect, %{port: nil} = state) do
    Logger.info("Attempting SSH reconnection...")
    new_state = connect(state)

    if new_state.port do
      # Notify console of reconnection
      if new_state.console do
        {pid, _ref} = new_state.console
        send(pid, {:console_data, "\r\n--- SSH reconnected ---\r\n"})
      end
    end

    {:noreply, new_state}
  end

  def handle_info(:reconnect, state) do
    # Already connected, ignore
    {:noreply, state}
  end

  def handle_info({:probe_timeout, from}, %{waiting: {from, _marker, _timer_ref, acc}} = state) do
    reply = if String.trim(acc) == "", do: :down, else: :noise
    GenServer.reply(from, reply)
    {:noreply, %{state | waiting: nil}}
  end

  def handle_info({:probe_timeout, _from}, state) do
    {:noreply, state}
  end

  def handle_info({:timeout, from}, state) do
    GenServer.reply(from, {:error, "Timeout waiting for device response"})
    {:noreply, %{state | waiting: nil}}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, %{console: {pid, ref}} = state) do
    {:noreply, %{state | console: nil}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.port do
      Port.close(state.port)
    end

    :ok
  end

  defp generate_marker do
    :crypto.strong_rand_bytes(8) |> Base.encode16()
  end

  # Elixir (IEx) output anchors the markers to the printed lines (`...START\r\n`)
  # to skip the PTY-echoed source. Shell output uses lenient bare markers,
  # matching the density device_mcp behaviour.
  defp match_markers(acc, marker, :elixir) do
    start_marker = "#{marker}_START\r\n"
    end_marker = "#{marker}_END\r\n"

    acc =
      if String.contains?(acc, start_marker) do
        [_, rest] = String.split(acc, start_marker, parts: 2)
        rest
      else
        acc
      end

    if String.contains?(acc, end_marker) do
      [result | _] = String.split(acc, end_marker)
      {:done, result}
    else
      {:cont, acc}
    end
  end

  defp match_markers(acc, marker, :shell) do
    start_marker = "#{marker}_START"
    end_marker = "#{marker}_END"

    acc =
      if String.contains?(acc, start_marker) do
        [_, rest] = String.split(acc, start_marker, parts: 2)

        rest
        |> String.replace_leading("\r\n", "")
        |> String.replace_leading("\r", "")
        |> String.replace_leading("\n", "")
      else
        acc
      end

    if String.contains?(acc, end_marker) do
      [result | _] = String.split(acc, end_marker)
      {:done, String.trim_trailing(result)}
    else
      {:cont, acc}
    end
  end
end
