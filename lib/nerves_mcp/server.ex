defmodule NervesMCP.Server do
  @moduledoc """
  MCP Server for interacting with Nerves devices.

  Exposes tools for evaluating Elixir code on connected Nerves devices
  via serial (UART) or SSH connections.
  """

  use EMCP.Server,
    name: "nerves-mcp",
    version: "0.1.0",
    tools: [
      NervesMCP.Tools.DeviceEval,
      NervesMCP.Tools.DeviceEvalOutput,
      NervesMCP.Tools.IsDeviceUp,
      NervesMCP.Tools.IsDeviceUpdatedTo
    ]
end
