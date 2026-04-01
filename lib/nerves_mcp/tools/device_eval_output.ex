defmodule NervesMCP.Tools.DeviceEvalOutput do
  @moduledoc """
  Evaluate Elixir code on a connected Nerves device and capture IO output.

  Unlike `device_eval` which returns the expression's return value,
  this tool captures what the code prints to stdout (IO.puts, IO.write, etc.)
  and returns both the output and the result.
  """

  @behaviour EMCP.Tool

  @impl EMCP.Tool
  def name, do: "device_eval_output"

  @impl EMCP.Tool
  def description, do: "Evaluate Elixir code on the connected Nerves device and capture IO output along with the result"

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
            NervesMCP.Connection.UART.eval_output(code, timeout)

          :ssh ->
            NervesMCP.Connection.SSH.eval_output(code, timeout)

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
