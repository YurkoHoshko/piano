defmodule PianoWeb.AdminAuth do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    token = conn.params["token"] || get_session(conn, "admin_token")
    expected = Application.get_env(:piano, :admin_token, "piano_admin")

    if token == expected do
      put_session(conn, "admin_token", token)
    else
      conn
      |> put_flash(:error, "Unauthorized - add ?token=<admin_token> to URL")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
