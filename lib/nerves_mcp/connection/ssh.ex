defmodule NervesMCP.Connection.SSH do
  @moduledoc """
  Handles SSH connection to a Nerves device.

  Uses a Port to maintain an interactive SSH session and evaluate Elixir code.
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def eval(code, timeout \\ 15000) do
    GenServer.call(__MODULE__, {:eval, code, timeout}, timeout + 1000)
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

  @impl true
  def init(_opts) do
    config = Application.get_env(:nerves_mcp, :connection, [])

    host = Keyword.fetch!(config, :host)
    user = Keyword.get(config, :user, "root")
    port = Keyword.get(config, :port, 22)

    ssh_args = [
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-o", "ServerAliveInterval=60",
      "-p", "#{port}",
      "-tt",
      "#{user}@#{host}"
    ]

    port_ref = Port.open({:spawn_executable, System.find_executable("ssh")}, [
      :binary,
      :exit_status,
      args: ssh_args
    ])

    {:ok, %{port: port_ref, buffer: "", waiting: nil, console: nil}}
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

  @impl true
  def handle_call({:eval, code, timeout}, from, state) do
    # Send the code followed by newline to execute in IEx
    # We wrap in a unique marker to identify our output
    marker = generate_marker()

    Logger.info("Running code on device:")
    Logger.info(code)

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
    Logger.info("Wrapped code:")
    Logger.info(wrapped_code)

    Port.command(state.port, wrapped_code <> "\n\n")

    timer_ref = Process.send_after(self(), {:timeout, from}, timeout)

    {:noreply, %{state | waiting: {from, marker, timer_ref, ""}}}
  end

  @impl true
  def handle_cast({:send_raw, data}, state) do
    Port.command(state.port, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port, waiting: nil, console: nil} = state) do
    Logger.info("not awaited: #{inspect(data)}")
    # Discard data when not waiting for a response
    {:noreply, state}
  end

  def handle_info({port, {:data, data}}, %{port: port, waiting: nil, console: {pid, _ref}} = state) do
    send(pid, {:console_data, data})
    {:noreply, state}
  end

  def handle_info({port, {:data, data}}, %{port: port, waiting: {from, marker, timer_ref, acc}} = state) do
    Logger.info("recv: #{inspect(data)}")
    new_acc = acc <> data

    start_marker = "#{marker}_START\r\n"
    end_marker = "#{marker}_END\r\n"
    Logger.info("Looking for start: #{inspect(start_marker)}")
    new_acc =
    if String.contains?(new_acc, start_marker) do
      [_, new_acc] = String.split(new_acc, start_marker, parts: 2)
      Logger.info("Accumulated: \n#{new_acc}")
      Logger.info("Found start..")
      new_acc
    else
      new_acc
    end

    Logger.info("Looking for end: #{inspect(end_marker)}")
    if String.contains?(new_acc, end_marker) do
      Logger.info("Found end..")
      [result | _] = String.split(new_acc, end_marker)
      Logger.info("End acc: \n#{result}")
      Process.cancel_timer(timer_ref)

      GenServer.reply(from, {:ok, result})

      {:noreply, %{state | waiting: nil}}
    else
      {:noreply, %{state | waiting: {from, marker, timer_ref, new_acc}}}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("SSH process exited with status: #{status}")

    if state.waiting do
      {from, _marker, timer_ref, _acc} = state.waiting
      Process.cancel_timer(timer_ref)
      GenServer.reply(from, {:error, "SSH connection closed unexpectedly"})
    end

    {:stop, {:ssh_exit, status}, %{state | waiting: nil}}
  end

  def handle_info({:timeout, from}, state) do
    GenServer.reply(from, {:error, "Timeout waiting for device response"})
    {:noreply, %{state | waiting: nil}}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, %{console: {pid, ref}} = state) do
    {:noreply, %{state | console: nil}}
  end

  def handle_info(msg, state) do
    Logger.debug("unexpected message: #{inspect(msg)}")
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
end
