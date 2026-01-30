defmodule NervesMCP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Mix.env() != :test do
        config = Application.get_env(:nerves_mcp, :connection, [])
        connection_type = Keyword.get(config, :type, :uart)

        connection_children =
          case connection_type do
            :uart -> [NervesMCP.Connection.UART]
            :ssh -> [NervesMCP.Connection.SSH]
          end

        port = Application.get_env(:nerves_mcp, :port, 8080)

        [
          NervesMCP.History,
          Anubis.Server.Registry,
          {NervesMCP.Server, transport: :streamable_http},
          {Bandit, plug: NervesMCP.Router, port: port}
        ] ++ connection_children
      else
        []
      end
    opts = [strategy: :one_for_one, name: NervesMCP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
