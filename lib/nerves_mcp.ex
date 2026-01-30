defmodule NervesMCP do
  @moduledoc """
  MCP Server for interacting with Nerves devices.

  ## Running the Server

  Start with `mix run --no-halt` or `iex -S mix`.

  The MCP server will be available at: `http://localhost:8080/mcp`

  ## Configuration

  Configure in your `config/config.exs`:

  ### HTTP Server Port

      config :nerves_mcp, :port, 8080

  ### UART (Serial) Connection

      config :nerves_mcp, :connection,
        type: :uart,
        port: "/dev/ttyUSB2",
        speed: 115_200

  ### SSH Connection

      config :nerves_mcp, :connection,
        type: :ssh,
        host: "nerves.local",
        user: "root",
        port: 22

  ## Interactive Console

  Call `NervesMCP.console()` to enter an interactive console session.
  Type `#quit` to exit and return to IEx, or `#history` to view buffered output.

  ## Output History

  Device output that arrives when no console is attached is stored in a
  circular buffer. Call `NervesMCP.history()` to view it, or use `#history`
  in the console.
  """

  @doc """
  Opens an interactive console to the connected device.

  Displays all incoming data from the device and allows you to send
  commands directly. Type `#quit` to exit the console and return to IEx.
  """
  def console do
    config = Application.get_env(:nerves_mcp, :connection, [])
    connection_type = Keyword.get(config, :type, :uart)

    connection_module =
      case connection_type do
        :uart -> NervesMCP.Connection.UART
        :ssh -> NervesMCP.Connection.SSH
      end

    # Start a process to receive and display console data
    parent = self()

    receiver =
      spawn_link(fn ->
        receive_loop(parent)
      end)

    # Attach the receiver process to get console data
    connection_module.attach_console(receiver)

    IO.puts("Connected to device console. Commands: #quit, #history")
    IO.puts("---")

    try do
      input_loop(connection_module)
    after
      # Clean up: stop receiver and detach console
      send(receiver, :stop)
      connection_module.detach_console()
    end

    IO.puts("---")
    IO.puts("Console closed.")
    :ok
  end

  @doc """
  Prints the buffered device output history.

  All device output that arrives when no console is attached is stored
  in a circular buffer. Use this to view what you might have missed.
  """
  def history do
    IO.puts(NervesMCP.History.get())
    :ok
  end

  def exit do
    IO.puts("Exiting...")
    System.halt(0)
  end

  defp receive_loop(parent, buffer \\ <<>>) do
    receive do
      {:console_data, data} ->
        combined = buffer <> data
        {complete, incomplete} = split_utf8(combined)

        if byte_size(complete) > 0 do
          IO.write(complete)
        end

        receive_loop(parent, incomplete)

      :stop ->
        # Write any remaining buffer on exit
        if byte_size(buffer) > 0 do
          IO.write(buffer)
        end

        :ok
    end
  end

  # Split binary into complete UTF-8 characters and trailing incomplete bytes
  defp split_utf8(binary) do
    size = byte_size(binary)

    if size == 0 do
      {<<>>, <<>>}
    else
      # Find how many trailing bytes might be incomplete
      incomplete_count = trailing_incomplete_bytes(binary, size)
      complete_size = size - incomplete_count
      <<complete::binary-size(complete_size), incomplete::binary>> = binary
      {complete, incomplete}
    end
  end

  # Count trailing bytes that form an incomplete UTF-8 sequence
  defp trailing_incomplete_bytes(binary, size) do
    # Check last 1-4 bytes for incomplete sequence
    check_from = max(0, size - 4)

    size
    |> Range.new(check_from + 1, -1)
    |> Enum.reduce_while(0, fn pos, _acc ->
      idx = pos - 1
      <<_::binary-size(idx), byte, _rest::binary>> = binary

      cond do
        # ASCII or valid end of multi-byte - everything complete
        byte <= 127 ->
          {:halt, 0}

        # Continuation byte (10xxxxxx) - keep looking back
        byte in 128..191 ->
          {:cont, size - idx}

        # 2-byte start (110xxxxx) - need 1 more
        byte in 192..223 ->
          remaining = size - idx
          {:halt, if(remaining < 2, do: remaining, else: 0)}

        # 3-byte start (1110xxxx) - need 2 more
        byte in 224..239 ->
          remaining = size - idx
          {:halt, if(remaining < 3, do: remaining, else: 0)}

        # 4-byte start (11110xxx) - need 3 more
        byte in 240..247 ->
          remaining = size - idx
          {:halt, if(remaining < 4, do: remaining, else: 0)}

        # Invalid UTF-8 byte - treat as complete to avoid infinite buffering
        true ->
          {:halt, 0}
      end
    end)
  end

  defp input_loop(connection_module) do
    case IO.gets("") do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      input when is_binary(input) ->
        trimmed = String.trim_trailing(input, "\n")

        case trimmed do
          "#quit" ->
            :ok

          "#history" ->
            IO.puts("--- History ---")
            IO.puts(NervesMCP.History.get())
            IO.puts("--- End History ---")
            input_loop(connection_module)

          _ ->
            connection_module.send_raw(input)
            input_loop(connection_module)
        end
    end
  end
end
