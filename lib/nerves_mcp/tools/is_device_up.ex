defmodule NervesMCP.Tools.IsDeviceUp do
  @moduledoc """
  Check if a connected Nerves device is up and responsive.

  Repeatedly attempts to read the device's firmware UUID via
  `Nerves.Runtime.KV.get_active("nerves_fw_uuid")`.
  Returns success with the UUID once the device responds, or an error
  if the total timeout is exceeded.
  """

  use Anubis.Server.Component, type: :tool

  schema do
    field(:timeout, :integer,
      description: "Total timeout in milliseconds to keep retrying (default: 60000)"
    )
  end

  @impl true
  def annotations do
    %{
      "readOnlyHint" => true,
      "destructiveHint" => false
    }
  end

  @eval_timeout 5_000
  @retry_pause 2_000

  @impl true
  def execute(params, frame) do
    total_timeout = params[:timeout] || 60_000
    deadline = System.monotonic_time(:millisecond) + total_timeout

    config = Application.get_env(:nerves_mcp, :connection, [])
    connection_type = Keyword.get(config, :type, :uart)

    result = poll_device(connection_type, deadline)

    alias Anubis.Server.Response

    case result do
      {:ok, uuid} ->
        response =
          Response.tool()
          |> Response.text("Device is up. Firmware UUID: #{uuid}")

        {:reply, response, frame}

      {:error, reason} ->
        {:error, Anubis.MCP.Error.execution(reason), frame}
    end
  end

  defp poll_device(connection_type, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, "Timed out waiting for device to come up"}
    else
      eval_timeout = min(@eval_timeout, remaining)

      case try_eval(connection_type, eval_timeout) do
        {:ok, uuid} when uuid != "" ->
          {:ok, String.trim(uuid)}

        _ ->
          maybe_reconnect(connection_type)
          Process.sleep(min(@retry_pause, max(0, deadline - System.monotonic_time(:millisecond))))
          poll_device(connection_type, deadline)
      end
    end
  end

  defp try_eval(connection_type, timeout) do
    code = ~s|Nerves.Runtime.KV.get_active("nerves_fw_uuid")|

    try do
      case connection_type do
        :uart -> NervesMCP.Connection.UART.eval(code, timeout)
        :ssh -> NervesMCP.Connection.SSH.eval(code, timeout)
        other -> {:error, "Unknown connection type: #{inspect(other)}"}
      end
    catch
      :exit, _ -> {:error, "connection unavailable"}
    end
  end

  defp maybe_reconnect(:ssh) do
    try do
      NervesMCP.Connection.SSH.reconnect()
    catch
      :exit, _ -> :ok
    end
  end

  defp maybe_reconnect(_), do: :ok
end
