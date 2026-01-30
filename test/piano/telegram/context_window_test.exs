defmodule Piano.Telegram.ContextWindowTest do
  use ExUnit.Case, async: false

  alias Piano.Telegram.ContextWindow

  setup do
    Application.put_env(:piano, :telegram_context_window_size, 50)

    case :ets.whereis(:piano_telegram_context_window) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(:piano_telegram_context_window)
    end

    :ok
  end

  test "records only group/supergroup and returns recent messages" do
    msg1 = %ExGram.Model.Message{
      message_id: 1,
      chat: %ExGram.Model.Chat{id: -10, type: "group", title: "G"},
      from: %ExGram.Model.User{id: 1, username: "a", first_name: "A", last_name: nil}
    }

    msg2 = %ExGram.Model.Message{
      message_id: 2,
      chat: %ExGram.Model.Chat{id: -10, type: "group", title: "G"},
      from: %ExGram.Model.User{id: 2, username: "b", first_name: "B", last_name: nil}
    }

    msg_private = %ExGram.Model.Message{
      message_id: 99,
      chat: %ExGram.Model.Chat{id: 123, type: "private", title: nil},
      from: %ExGram.Model.User{id: 3, username: "c", first_name: "C", last_name: nil}
    }

    :ok = ContextWindow.record(msg1, "one")
    :ok = ContextWindow.record(msg2, "two")
    :ok = ContextWindow.record(msg_private, "nope")

    recent = ContextWindow.recent(-10, limit: 10)
    assert Enum.map(recent, & &1.text) == ["one", "two"]
    assert ContextWindow.recent(123, limit: 10) == []
  end

  test "keeps only the last N messages and can exclude current message_id" do
    Application.put_env(:piano, :telegram_context_window_size, 3)
    chat = %ExGram.Model.Chat{id: -10, type: "supergroup", title: "SG"}

    for {id, text} <- [{1, "one"}, {2, "two"}, {3, "three"}, {4, "four"}] do
      msg = %ExGram.Model.Message{
        message_id: id,
        chat: chat,
        from: %ExGram.Model.User{id: id, username: "u#{id}", first_name: "U", last_name: nil}
      }

      :ok = ContextWindow.record(msg, text)
    end

    recent = ContextWindow.recent(-10, limit: 10)
    assert Enum.map(recent, & &1.text) == ["two", "three", "four"]

    recent_excl = ContextWindow.recent(-10, limit: 10, exclude_message_id: 4)
    assert Enum.map(recent_excl, & &1.text) == ["two", "three"]
  end

  test "since_last_tag_or_last_n returns messages after last tag, else last N" do
    chat_id = -10
    chat = %ExGram.Model.Chat{id: chat_id, type: "group", title: "G"}

    for {id, text} <- [{1, "a"}, {2, "b"}, {3, "c"}, {4, "d"}] do
      msg = %ExGram.Model.Message{
        message_id: id,
        chat: chat,
        from: %ExGram.Model.User{id: id, username: "u#{id}", first_name: "U", last_name: nil}
      }

      :ok = ContextWindow.record(msg, text)
    end

    # No tag yet -> last 2
    last2 = ContextWindow.recent(chat_id, mode: :since_last_tag_or_last_n, limit: 2)
    assert Enum.map(last2, & &1.text) == ["c", "d"]

    :ok = ContextWindow.mark_tagged(chat_id, 2)
    recent_after = ContextWindow.recent(chat_id, mode: :since_last_tag_or_last_n, limit: 2)
    assert Enum.map(recent_after, & &1.text) == ["c", "d"]
  end
end
