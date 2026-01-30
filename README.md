# NervesMCP

An MCP (Model Context Protocol) server for interacting with Nerves devices. Enables AI assistants to evaluate Elixir code on embedded devices connected via UART or SSH.

## Installation

Add to your dependencies:

```elixir
def deps do
  [
    {:nerves_mcp, "~> 0.1.0"}
  ]
end
```

## Configuration

Configure the connection type and MCP server port in `config/config.exs`:

### UART (Serial) Connection

```elixir
config :nerves_mcp, :port, 13000

config :nerves_mcp, :connection,
  type: :uart,
  port: "/dev/ttyUSB0",
  speed: 115_200
```

### SSH Connection

```elixir
config :nerves_mcp, :port, 13000

config :nerves_mcp, :connection,
  type: :ssh,
  host: "nerves.local",
  user: "root",
  port: 22
```

## Running

```bash
iex -S mix
```

The MCP server will be available at `http://localhost:13000/mcp` (or your configured port).

## MCP Tools

### device_eval

Evaluates Elixir code on the device and returns the expression's return value.

### device_eval_output

Evaluates Elixir code and captures IO output (what the code prints via `IO.puts`, `IO.write`, etc.) in addition to the return value.

## Interactive Console

From IEx, you can open an interactive console to the device:

```elixir
iex> console()
Connected to device console. Commands: #quit, #history
---
```

This lets you interact directly with the device's IEx shell. Commands:

- `#quit` - Exit the console and return to local IEx
- `#history` - Display buffered output history

## Output History

Device output is stored in a circular buffer, even when no console is attached. This includes output from MCP tool calls.

```elixir
iex> history()
```

Or use `#history` while in the console.

## License

Apache-2.0
