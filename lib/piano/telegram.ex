defmodule Piano.Telegram do
  use Ash.Domain

  resources do
    resource Piano.Telegram.Session
  end
end
