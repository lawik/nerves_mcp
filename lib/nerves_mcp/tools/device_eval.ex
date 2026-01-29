defmodule NervesMCP.Tools.DeviceEval do
  @moduledoc """
  Evaluate Elixir code on a connected Nerves device.

  The device must be connected via serial (UART) or SSH.
  Configure the connection in the application config.

  Returns the result of the evaluated expression as inspected output.
  """

  use Anubis.Server.Component, type: :tool

  require Logger

  schema do
    field :code, {:required, :string}, description: "Elixir code to evaluate on the device"
    field :timeout, :integer, description: "Timeout in milliseconds (default: 15000)"
  end

  @impl true
  def annotations do
    %{
      "readOnlyHint" => false,
      "destructiveHint" => true
    }
  end

  @impl true
  def execute(params, frame) do
    IO.inspect(params, label: "params")
    IO.inspect(frame, label: "frame")
    code = params[:code]
    timeout = params[:timeout] || 15000
    Logger.info("device_eval:")
    Logger.info(code)

    config = Application.get_env(:nerves_mcp, :connection, [])
    connection_type = Keyword.get(config, :type, :uart)

    result =
      case connection_type do
        :uart ->
          NervesMCP.Connection.UART.eval(code, timeout)

        :ssh ->
          NervesMCP.Connection.SSH.eval(code, config, timeout)

        other ->
          {:error, "Unknown connection type: #{inspect(other)}"}
      end

    alias Anubis.Server.Response

    case result do
      {:ok, output} ->
        response = Response.tool() |> Response.text(output)
        {:reply, response, frame}

      {:error, reason} ->
        {:error, Anubis.MCP.Error.execution(reason), frame}
    end
  end
end
