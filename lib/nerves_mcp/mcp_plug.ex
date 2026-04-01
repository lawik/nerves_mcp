defmodule NervesMCP.MCPPlug do
  @moduledoc false

  # Thin wrapper around Anubis.Server.Transport.StreamableHTTP.Plug
  # that defers init to call-time, avoiding compile-time persistent_term access.

  @behaviour Plug

  alias Anubis.Server.Transport.StreamableHTTP

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    opts = StreamableHTTP.Plug.init(opts)
    StreamableHTTP.Plug.call(conn, opts)
  end
end
