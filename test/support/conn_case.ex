defmodule PianoWeb.ConnCase do
  @moduledoc """
  Test helpers for endpoint and connection tests.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint PianoWeb.Endpoint

      use PianoWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import PianoWeb.ConnCase
    end
  end

  setup tags do
    Piano.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
