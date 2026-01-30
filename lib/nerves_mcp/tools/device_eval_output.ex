defmodule NervesMCP.Tools.DeviceEvalOutput do
  @moduledoc """
  Evaluate Elixir code on a connected Nerves device and capture IO output.

  Unlike `device_eval` which returns the expression's return value,
  this tool captures what the code prints to stdout (IO.puts, IO.write, etc.)
  and returns both the output and the result.
  """

  use Anubis.Server.Component, type: :tool

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
    code = params[:code]
    timeout = params[:timeout] || 15000

    config = Application.get_env(:nerves_mcp, :connection, [])
    connection_type = Keyword.get(config, :type, :uart)

    result =
      case connection_type do
        :uart ->
          NervesMCP.Connection.UART.eval_output(code, timeout)

        :ssh ->
          NervesMCP.Connection.SSH.eval_output(code, timeout)

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
