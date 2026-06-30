defmodule NervesMCP.Tools.ShellEval do
  @moduledoc """
  Run a raw shell command on the connected device.

  Exposed (under the `device_eval` name) when the device probe detects a serial
  connection that responds but does not run Elixir. Mirrors the density
  `device_mcp` behaviour: the command is wrapped in `echo` markers and the
  output between them is returned.
  """

  @behaviour EMCP.Tool

  @impl EMCP.Tool
  def name, do: "device_eval"

  @impl EMCP.Tool
  def description,
    do:
      "Run a raw shell command on the connected device and return the output (device is not running Elixir)"

  @impl EMCP.Tool
  def input_schema do
    %{
      type: :object,
      properties: %{
        command: %{type: :string, description: "Shell command to run on the device"},
        timeout: %{type: :integer, description: "Timeout in milliseconds (default: 15000)"}
      },
      required: [:command]
    }
  end

  @impl EMCP.Tool
  def call(_conn, args) do
    command = args["command"]
    timeout = args["timeout"] || 15000

    config = Application.get_env(:nerves_mcp, :connection, [])
    connection_type = Keyword.get(config, :type, :uart)

    result =
      try do
        case connection_type do
          :uart -> NervesMCP.Connection.UART.shell_eval(command, timeout)
          :ssh -> NervesMCP.Connection.SSH.shell_eval(command, timeout)
          other -> {:error, "Unknown connection type: #{inspect(other)}"}
        end
      catch
        :exit, {:noproc, _} ->
          {:error, "Device connection not available (process not running)"}

        :exit, reason ->
          {:error, "Device connection error: #{inspect(reason)}"}
      end

    case result do
      {:ok, output} -> EMCP.Tool.response([%{"type" => "text", "text" => output}])
      {:error, reason} -> EMCP.Tool.error(reason)
    end
  end
end
