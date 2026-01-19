defmodule PianoWeb.PageController do
  use PianoWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end
end
