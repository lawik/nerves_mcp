defmodule NervesMCP.Router do
  @moduledoc false

  use Plug.Router

  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  forward("/mcp",
    to: EMCP.Transport.StreamableHTTP,
    init_opts: [server: NervesMCP.Server]
  )

  match _ do
    send_resp(conn, 404, "not found")
  end
end
