defmodule PianoWeb.Router do
  use PianoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PianoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    #   plug PianoWeb.AdminAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :codex_api do
  end

  scope "/", PianoWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  import Phoenix.LiveDashboard.Router

  scope "/" do
    pipe_through [:browser, :admin]

    live_dashboard "/dashboard",
      metrics: PianoWeb.Telemetry,
      ecto_repos: [Piano.Repo]
  end

  if Application.compile_env(:piano, :test_routes, false) do
    scope "/v1", PianoWeb do
      pipe_through :codex_api

      post "/chat/completions", CodexReplayController, :chat_completions
      post "/responses", CodexReplayController, :responses
      get "/models", CodexReplayController, :models
    end
  end

  pipeline :mcp do
    plug :accepts, ["json", "sse"]
  end

  # MCP (Model Context Protocol) endpoint for AI tools
  scope "/mcp" do
    pipe_through :mcp

    forward "/", AshAi.Mcp.Router,
      otp_app: :piano,
      protocol_version_statement: "2024-11-05"
  end
end
