defmodule NervesMCP.Server do
  @moduledoc """
  MCP Server for interacting with Nerves devices.

  The exposed tool list is dynamic: `server/0` is evaluated on every request by
  the transport, so it reflects the current device state as detected by
  `NervesMCP.DeviceProbe`.

    * `:nerves` — full Elixir + Nerves tooling
    * `:elixir` — Elixir eval only (Elixir runs, but not confirmed Nerves)
    * `:shell`  — degraded raw shell tooling (device responds but no Elixir)
    * `:down` / `:unknown` — just the wait/status tools

  `is_device_up`, `is_device_updated_to` and `device_status` are always offered
  so you can wait for a device to come up regardless of its current state.

  On a state change `DeviceProbe` broadcasts `notifications/tools/list_changed`
  (the `listChanged` capability is advertised at initialize) so connected clients
  refetch the list.
  """

  alias NervesMCP.Tools

  @base [Tools.IsDeviceUp, Tools.IsDeviceUpdatedTo, Tools.DeviceStatus]

  @instructions """
  Tools for interacting with a connected Nerves device over serial or SSH.

  The available tools depend on what is currently on the other end of the
  connection (see `device_status`):

    * A confirmed Nerves device offers `device_eval`/`device_eval_output`
      (Elixir), plus `grep_ring_logger` and `grep_dmesg`.
    * A non-Nerves serial that still responds offers `device_eval`/
      `device_eval_output` as raw shell commands.
    * When the device is down, only the wait/status tools are offered.

  Use `is_device_up` / `is_device_updated_to` to wait for a device to come up
  after a reboot or firmware update.
  """

  def server do
    NervesMCP.DeviceProbe.touch()

    EMCP.Server.new(
      name: "nerves-mcp",
      version: "0.1.0",
      instructions: @instructions,
      tools: tools_for(NervesMCP.DeviceProbe.mode())
    )
  end

  defp tools_for(:nerves) do
    @base ++ [Tools.DeviceEval, Tools.DeviceEvalOutput, Tools.GrepRingLogger, Tools.GrepDmesg]
  end

  defp tools_for(:elixir) do
    @base ++ [Tools.DeviceEval, Tools.DeviceEvalOutput]
  end

  defp tools_for(:shell) do
    @base ++ [Tools.ShellEval, Tools.ShellEvalOutput]
  end

  defp tools_for(_), do: @base
end
