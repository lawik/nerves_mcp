import Config

# HTTP server port for MCP
config :nerves_mcp, :port, 13000

# UART connection to Nerves device
config :nerves_mcp, :connection,
  type: :uart,
  port: "/dev/ttyUSB2",
  speed: 115_200

# SSH connection (alternative)
# config :nerves_mcp, :connection,
#   type: :ssh,
#   host: "nerves.local",
#   user: "root",
#   port: 22

config :bun, :version, "1.3.0"
