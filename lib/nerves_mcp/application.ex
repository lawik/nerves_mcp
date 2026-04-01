defmodule NervesMCP.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    EMCP.SessionStore.ETS.init()

    config = Application.get_env(:nerves_mcp, :connection, [])

    children =
      if Keyword.has_key?(config, :type) do
        # Connection configured via config.exs — start everything
        connection_child =
          case Keyword.fetch!(config, :type) do
            :uart -> NervesMCP.Connection.UART
            :ssh -> NervesMCP.Connection.SSH
          end

        port = Application.get_env(:nerves_mcp, :port, 13000)

        [
          NervesMCP.History,
          {Bandit, plug: NervesMCP.Router, port: port},
          connection_child
        ]
      else
        # No config — CLI.run/1 will start children later
        []
      end

    opts = [strategy: :one_for_one, name: NervesMCP.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
