defmodule NervesMCP.Tools.DeviceEval do
  @moduledoc """
  Evaluate Elixir code on a connected Nerves device.

  The device must be connected via serial (UART) or SSH.
  Configure the connection in the application config.

  Returns the result of the evaluated expression as inspected output.
  """

  @behaviour EMCP.Tool

  @impl EMCP.Tool
  def name, do: "device_eval"

  @impl EMCP.Tool
  def description,
    do: "Evaluate Elixir code on the connected Nerves device and return the expression result"

  @impl EMCP.Tool
  def input_schema do
    %{
      type: :object,
      properties: %{
        code: %{type: :string, description: "Elixir code to evaluate on the device"},
        timeout: %{type: :integer, description: "Timeout in milliseconds (default: 15000)"}
      },
      required: [:code]
    }
  end

  @impl EMCP.Tool
  def call(_conn, args) do
    code = args["code"]
    timeout = args["timeout"] || 15000

    config = Application.get_env(:nerves_mcp, :connection, [])
    connection_type = Keyword.get(config, :type, :uart)

    result =
      try do
        case connection_type do
          :uart ->
            NervesMCP.Connection.UART.eval(code, timeout)

          :ssh ->
            NervesMCP.Connection.SSH.eval(code, timeout)

          other ->
            {:error, "Unknown connection type: #{inspect(other)}"}
        end
      catch
        :exit, {:noproc, _} ->
          {:error, "Device connection not available (process not running)"}

        :exit, reason ->
          {:error, "Device connection error: #{inspect(reason)}"}
      end

    case result do
      {:ok, output} ->
        EMCP.Tool.response([%{"type" => "text", "text" => output}])

      {:error, reason} ->
        EMCP.Tool.error(reason)
    end
  end
end
