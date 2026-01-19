defmodule PianoWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint PianoWeb.Endpoint

      use PianoWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import PianoWeb.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
