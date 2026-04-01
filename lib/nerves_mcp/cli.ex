defmodule NervesMCP.CLI do
  @moduledoc """
  CLI argument parsing and connection setup for NervesMCP.

  CLI args override values from config/config.exs. If no args are provided
  but config exists, the config values are used as-is.

  Supports two connection modes:

  **Serial (UART):**
      nerves_mcp /dev/ttyUSB0
      nerves_mcp --serial /dev/ttyUSB0 --speed 115200

  **SSH:**
      nerves_mcp nerves.local
      nerves_mcp --ssh nerves.local --user root --ssh-port 22

  Common options:
      --port PORT    MCP server port (default: 13000)
  """

  @serial_patterns ["/dev/tty", "/dev/cu.", "/dev/serial"]

  def main(args) do
    run(args)
    repl()
  end

  def repl do
    case IO.gets("> ") do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      input when is_binary(input) ->
        input
        |> String.trim()
        |> handle_command()

        repl()
    end
  end

  defp handle_command("console"), do: NervesMCP.console()
  defp handle_command("history"), do: NervesMCP.history()
  defp handle_command("exit"), do: NervesMCP.exit()
  defp handle_command("help"), do: IO.puts("Commands: console, history, exit, help")
  defp handle_command(""), do: :ok
  defp handle_command(other), do: IO.puts("Unknown command: #{other}. Type 'help' for commands.")

  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          serial: :string,
          ssh: :string,
          port: :integer,
          speed: :integer,
          user: :string,
          ssh_port: :integer
        ],
        aliases: [
          p: :port,
          s: :speed,
          u: :user
        ]
      )

    existing_config = Application.get_env(:nerves_mcp, :connection, [])
    connection = resolve_connection(opts, positional, existing_config)
    mcp_port = Keyword.get(opts, :port, Application.get_env(:nerves_mcp, :port, 13000))

    Application.put_env(:nerves_mcp, :connection, connection)
    Application.put_env(:nerves_mcp, :port, mcp_port)

    start_children(connection, mcp_port)

    connection_desc =
      case Keyword.fetch!(connection, :type) do
        :uart ->
          "serial #{Keyword.fetch!(connection, :port)} @ #{Keyword.get(connection, :speed, 115_200)}"

        :ssh ->
          "ssh #{Keyword.get(connection, :user, "root")}@#{Keyword.fetch!(connection, :host)}:#{Keyword.get(connection, :port, 22)}"
      end

    IO.puts("NervesMCP started on port #{mcp_port} via #{connection_desc}")
  end

  defp resolve_connection(opts, positional, existing_config) do
    cond do
      # Explicit --serial flag
      Keyword.has_key?(opts, :serial) ->
        serial_config(Keyword.fetch!(opts, :serial), opts, existing_config)

      # Explicit --ssh flag
      Keyword.has_key?(opts, :ssh) ->
        ssh_config(Keyword.fetch!(opts, :ssh), opts, existing_config)

      # First positional arg matches a serial device pattern
      match?([_ | _], positional) and serial_device?(hd(positional)) ->
        serial_config(hd(positional), opts, existing_config)

      # First positional arg is treated as SSH host
      match?([_ | _], positional) ->
        ssh_config(hd(positional), opts, existing_config)

      # No args — fall back to existing config
      Keyword.has_key?(existing_config, :type) ->
        apply_overrides(existing_config, opts)

      true ->
        IO.puts("""
        Usage: nerves_mcp <device-or-host> [options]

        Examples:
          nerves_mcp /dev/ttyUSB0                   # Serial connection
          nerves_mcp /dev/ttyUSB0 --speed 9600      # Serial with custom baud rate
          nerves_mcp nerves.local                    # SSH connection
          nerves_mcp nerves.local --user root        # SSH with custom user
          nerves_mcp --serial /dev/ttyACM0           # Explicit serial
          nerves_mcp --ssh 192.168.1.100             # Explicit SSH

        Options:
          --port PORT        MCP server port (default: 13000)
          --speed BAUD       Serial baud rate (default: 115200)
          --user USER        SSH user (default: root)
          --ssh-port PORT    SSH port (default: 22)

        Connection can also be configured in config/config.exs.
        CLI arguments override config values.
        """)

        System.halt(1)
    end
  end

  defp serial_config(device, opts, existing_config) do
    base =
      if Keyword.get(existing_config, :type) == :uart do
        existing_config
      else
        [type: :uart, speed: 115_200]
      end

    base
    |> Keyword.put(:port, device)
    |> apply_overrides(opts)
  end

  defp ssh_config(host, opts, existing_config) do
    base =
      if Keyword.get(existing_config, :type) == :ssh do
        existing_config
      else
        [type: :ssh, user: "root", port: 22]
      end

    base
    |> Keyword.put(:host, host)
    |> apply_overrides(opts)
  end

  defp apply_overrides(config, opts) do
    config
    |> maybe_put(:speed, Keyword.get(opts, :speed))
    |> maybe_put(:user, Keyword.get(opts, :user))
    |> maybe_put(:port, Keyword.get(opts, :ssh_port))
  end

  defp maybe_put(config, _key, nil), do: config
  defp maybe_put(config, key, value), do: Keyword.put(config, key, value)

  defp serial_device?(path) do
    Enum.any?(@serial_patterns, &String.starts_with?(path, &1))
  end

  defp start_children(connection, mcp_port) do
    connection_child =
      case Keyword.fetch!(connection, :type) do
        :uart -> NervesMCP.Connection.UART
        :ssh -> NervesMCP.Connection.SSH
      end

    children = [
      NervesMCP.History,
      {NervesMCP.Server, transport: :streamable_http},
      {Bandit, plug: NervesMCP.Router, port: mcp_port},
      connection_child
    ]

    for child <- children do
      Supervisor.start_child(NervesMCP.Supervisor, child)
    end
  end
end
