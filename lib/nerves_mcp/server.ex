defmodule NervesMCP.Server do
  @moduledoc """
  MCP Server for interacting with Nerves devices.

  Exposes tools for evaluating Elixir code on connected Nerves devices
  via serial (UART) or SSH connections.
  """

  use Anubis.Server,
    name: "nerves-mcp",
    version: "0.1.0",
    capabilities: [:tools]

  component NervesMCP.Tools.DeviceEval
end
