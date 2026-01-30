defmodule Piano.Telegram.PromptTest do
  use ExUnit.Case, async: true

  alias Piano.Telegram.Prompt

  test "build/2 returns plain text for private chats" do
    msg = %{
      chat: %{id: 1, type: "private"},
      from: %{id: 2, username: "alice"}
    }

    assert Prompt.build(msg, "Hi") == "Hi"
  end

  test "build/2 adds group attribution and multi-user note" do
    msg = %{
      chat: %{id: -10, type: "group", title: "My Group"},
      from: %{id: 42, username: "alice"}
    }

    built =
      Prompt.build(msg, "Hello everyone",
        participants: 12,
        recent: [%{from: "@bob", text: "Earlier message"}]
      )

    assert built =~ "<chat_instructions>"
    assert built =~ "You are being messaged from Telegram messenger."
    assert built =~ "Chat name: My Group"
    assert built =~ "Participants: 12"
    assert built =~ "<invoked_by_user>@alice (telegram_user_id=42)</invoked_by_user>"
    assert built =~ "<chat_history>"
    assert built =~ "<message from=\"@bob\">Earlier message</message>"
    assert built =~ "\nHello everyone"
  end

  test "build/2 supports ExGram structs (no Access protocol)" do
    msg = %ExGram.Model.Message{
      chat: %ExGram.Model.Chat{id: -123, type: "supergroup", title: "X"},
      from: %ExGram.Model.User{id: 7, username: "bob", first_name: "Bob", last_name: nil}
    }

    built = Prompt.build(msg, "Yo")
    assert built =~ "<chat_instructions>"
    assert built =~ "You are being messaged from Telegram messenger."
    assert built =~ "Chat name: X"
    assert built =~ "<invoked_by_user>@bob (telegram_user_id=7)</invoked_by_user>"
    assert String.contains?(built, "\nYo\n")
  end
end
