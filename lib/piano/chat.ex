defmodule Piano.Chat do
  use Ash.Domain

  resources do
    resource Piano.Chat.Thread
    resource Piano.Chat.Message
  end
end
