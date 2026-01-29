defmodule Piano.Telegram do
  @moduledoc """
  Telegram domain resources and behaviors.
  """
  use Ash.Domain

  resources do
    resource Piano.Telegram.Session
  end
end
