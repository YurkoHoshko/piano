defmodule PianoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :piano

  @session_options [
    store: :cookie,
    key: "_piano_key",
    signing_salt: "piano_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :piano,
    gzip: false,
    only: PianoWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader

    # Ash AI Dev MCP server for local development
    # Available at http://localhost:4000/ash_ai/mcp
    plug AshAi.Mcp.Dev,
      otp_app: :piano,
      protocol_version_statement: "2024-11-05"
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug PianoWeb.Router
end
