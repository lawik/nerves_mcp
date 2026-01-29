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
  """
end
