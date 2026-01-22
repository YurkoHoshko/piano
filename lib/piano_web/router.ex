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

  scope "/", PianoWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/chat", ChatLive
  end

  scope "/admin", PianoWeb.Admin do
    pipe_through [:browser, :admin]

    live "/agents", AgentListLive
    live "/agents/:id", AgentEditLive
  end

  import Phoenix.LiveDashboard.Router

  scope "/" do
    pipe_through [:browser, :admin]

    live_dashboard "/dashboard",
      metrics: PianoWeb.Telemetry,
      ecto_repos: [Piano.Repo],
      additional_pages: [
        agents: PianoWeb.Admin.AgentsPage
      ]
  end
end
