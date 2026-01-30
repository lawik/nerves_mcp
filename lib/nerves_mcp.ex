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
  Type `#quit` to exit and return to IEx.
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

    IO.puts("Connected to device console. Type #quit to exit.")
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

  def exit do
    IO.puts("Exiting...")
    System.halt(0)
  end

  defp receive_loop(parent) do
    receive do
      {:console_data, data} ->
        IO.write(data)
        receive_loop(parent)

      :stop ->
        :ok
    end
  end

  defp input_loop(connection_module) do
    case IO.gets("") do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      input when is_binary(input) ->
        trimmed = String.trim_trailing(input, "\n")

        if trimmed == "#quit" do
          :ok
        else
          connection_module.send_raw(input)
          input_loop(connection_module)
        end
    end
  end
end
