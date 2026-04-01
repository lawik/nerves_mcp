defmodule NervesMCP.Router do
  @moduledoc false

  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  forward("/mcp",
    to: NervesMCP.MCPPlug,
    init_opts: [server: NervesMCP.Server, request_timeout: 30_000]
  )

  match _ do
    send_resp(conn, 404, "not found")
  end
end
