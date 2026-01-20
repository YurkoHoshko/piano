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
    
  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave  
  end

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
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
