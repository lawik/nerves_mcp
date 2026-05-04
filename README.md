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

## Usage

NervesMCP can be run as a Mix task or as a standalone escript. The first argument is either a serial device path or an SSH host — NervesMCP auto-detects which based on the path.

### Mix task

```bash
# Serial — auto-detected from /dev/tty* path
mix nerves_mcp /dev/ttyUSB0
mix nerves_mcp /dev/ttyUSB0 --speed 9600

# SSH — anything that isn't a serial path is treated as a host
mix nerves_mcp nerves.local
mix nerves_mcp nerves.local --user root --ssh-port 2222
```

### Escript

Build the escript and run it directly:

```bash
mix escript.build
./nerves_mcp /dev/ttyUSB0
./nerves_mcp nerves.local --user exnvr --port 4000
```

### Options

| Flag           | Description                        | Default   |
|----------------|------------------------------------|-----------|
| `--port`       | MCP server HTTP port               | `13000`   |
| `--speed`      | Serial baud rate                   | `115200`  |
| `--user`       | SSH username                       | `root`    |
| `--ssh-port`   | SSH port                           | `22`      |
| `--serial`     | Force serial mode (pass device)    |           |
| `--ssh`        | Force SSH mode (pass host)         |           |

Short aliases: `-p` (port), `-s` (speed), `-u` (user).

### Configuration file

Connection settings can also be defined in `config/config.exs`. CLI arguments override config values.

```elixir
# Serial
config :nerves_mcp, :port, 13000
config :nerves_mcp, :connection,
  type: :uart,
  port: "/dev/ttyUSB0",
  speed: 115_200

# Or SSH
config :nerves_mcp, :connection,
  type: :ssh,
  host: "nerves.local",
  user: "root",
  port: 22
```

With config in place, you can start without any arguments:

```bash
mix nerves_mcp
```

Or override specific values:

```bash
mix nerves_mcp --speed 9600    # use config but change baud rate
mix nerves_mcp other.local     # switch to a different host entirely
```

### Auto-detection

If the first argument starts with `/dev/tty`, `/dev/cu.`, or `/dev/serial`, it is treated as a serial device. Otherwise it is treated as an SSH host. Use `--serial` or `--ssh` to be explicit:

```bash
mix nerves_mcp --serial /dev/ttyACM0
mix nerves_mcp --ssh 192.168.1.100
```

### Connecting to the MCP server

Once running, the MCP server is available at:

```
http://localhost:13000/mcp
```

Or whatever port you specified with `--port`.

## MCP Tools

### device_eval

Evaluates Elixir code on the device and returns the expression's return value.

### device_eval_output

Evaluates Elixir code and captures IO output (what the code prints via `IO.puts`, `IO.write`, etc.) in addition to the return value.

### grep_ring_logger

Filters the device's `RingLogger` buffer by a substring or regex pattern. Optional `tail` returns only the last N matches.

### grep_dmesg

Filters the device's `dmesg` (kernel ring buffer) by a substring or regex pattern. Optional `tail` returns only the last N matches.

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
