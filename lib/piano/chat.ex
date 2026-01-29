defmodule Piano.Chat do
  @moduledoc """
  Chat domain resources and policies.
  """
  use Ash.Domain

  resources do
    resource Piano.Chat.Thread
    resource Piano.Chat.Message
  end
end
