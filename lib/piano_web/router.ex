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

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PianoWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/chat", ChatLive
  end

  scope "/admin", PianoWeb.Admin do
    pipe_through :browser

    live "/agents", AgentListLive
    live "/agents/:id", AgentEditLive
  end
end
