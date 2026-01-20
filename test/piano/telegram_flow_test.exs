defmodule Piano.TelegramFlowTest do
  use Piano.DataCase, async: false

  import Mox

  alias Piano.Agents.Agent
  alias Piano.Chat.Message
  alias Piano.Telegram.Bot

  setup :set_mox_global

  @mock_response %{
    "choices" => [
      %{
        "message" => %{
          "role" => "assistant",
          "content" => "Hello from the bot! How can I assist you?"
        },
        "finish_reason" => "stop"
      }
    ]
  }

  describe "telegram chat flow" do
    setup do
      {:ok, agent} =
        Ash.create(Agent,
          %{
            name: "Telegram Agent",
            model: "test-model",
            system_prompt: "You are a helpful Telegram bot."
          },
          action: :create
        )

      %{agent: agent}
    end

    test "handles incoming telegram message and sends response", %{agent: _agent} do
      chat_id = 123_456_789
      test_pid = self()
      placeholder_message_id = 42

      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:ok, @mock_response}
      end)

      Piano.Telegram.API.Mock
      |> stub(:send_chat_action, fn _chat_id, "typing", _opts ->
        {:ok, %{}}
      end)
      |> expect(:send_message, fn ^chat_id, "⏳ Processing...", _opts ->
        {:ok, %{message_id: placeholder_message_id}}
      end)
      |> expect(:edit_message_text, fn ^chat_id, ^placeholder_message_id, content, _opts ->
        send(test_pid, {:message_edited, content})
        {:ok, %{}}
      end)

      mock_msg = %{chat: %{id: chat_id}}

      Bot.handle({:text, "Hello bot", mock_msg}, nil)

      assert_receive {:message_edited, "Hello from the bot! How can I assist you?"}, 2000

      query = Ash.Query.for_read(Message, :read)
      {:ok, messages} = Ash.read(query)

      user_messages = Enum.filter(messages, &(&1.role == :user))
      agent_messages = Enum.filter(messages, &(&1.role == :agent))

      assert length(user_messages) == 1
      assert length(agent_messages) == 1

      [user_message] = user_messages
      assert user_message.content == "Hello bot"
      assert user_message.source == :telegram

      [agent_message] = agent_messages
      assert agent_message.content == "Hello from the bot! How can I assist you?"
    end

    test "stores telegram message with correct source", %{agent: _agent} do
      chat_id = 987_654_321
      test_pid = self()
      placeholder_message_id = 99

      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:ok, @mock_response}
      end)

      Piano.Telegram.API.Mock
      |> stub(:send_chat_action, fn _chat_id, _action, _opts -> {:ok, %{}} end)
      |> expect(:send_message, fn _chat_id, "⏳ Processing...", _opts ->
        {:ok, %{message_id: placeholder_message_id}}
      end)
      |> expect(:edit_message_text, fn _chat_id, ^placeholder_message_id, _content, _opts ->
        send(test_pid, :message_edited)
        {:ok, %{}}
      end)

      mock_msg = %{chat: %{id: chat_id}}

      Bot.handle({:text, "Test telegram source", mock_msg}, nil)

      assert_receive :message_edited, 2000

      query = Ash.Query.for_read(Message, :read)
      {:ok, messages} = Ash.read(query)

      user_message = Enum.find(messages, &(&1.role == :user))
      assert user_message != nil
      assert user_message.source == :telegram
      assert user_message.content == "Test telegram source"
    end

    test "handles error gracefully", %{agent: _agent} do
      chat_id = 111_222_333
      test_pid = self()
      placeholder_message_id = 77

      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:error, :llm_failure}
      end)

      Piano.Telegram.API.Mock
      |> stub(:send_chat_action, fn _chat_id, "typing", _opts ->
        {:ok, %{}}
      end)
      |> expect(:send_message, fn ^chat_id, "⏳ Processing...", _opts ->
        {:ok, %{message_id: placeholder_message_id}}
      end)
      |> expect(:edit_message_text, fn ^chat_id, ^placeholder_message_id, content, _opts ->
        send(test_pid, {:error_message_edited, content})
        {:ok, %{}}
      end)

      mock_msg = %{chat: %{id: chat_id}}

      Bot.handle({:text, "Trigger error", mock_msg}, nil)

      assert_receive {:error_message_edited, content}, 2000
      assert content =~ "error"
    end

    test "falls back to send_message when edit fails", %{agent: _agent} do
      chat_id = 555_666_777
      test_pid = self()
      placeholder_message_id = 123

      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:ok, @mock_response}
      end)

      Piano.Telegram.API.Mock
      |> stub(:send_chat_action, fn _chat_id, "typing", _opts ->
        {:ok, %{}}
      end)
      |> expect(:send_message, fn ^chat_id, "⏳ Processing...", _opts ->
        {:ok, %{message_id: placeholder_message_id}}
      end)
      |> expect(:edit_message_text, fn ^chat_id, ^placeholder_message_id, _content, _opts ->
        {:error, %{description: "Bad Request: message is not modified"}}
      end)
      |> expect(:send_message, fn ^chat_id, content, _opts ->
        send(test_pid, {:fallback_message_sent, content})
        {:ok, %{}}
      end)

      mock_msg = %{chat: %{id: chat_id}}

      Bot.handle({:text, "Test fallback", mock_msg}, nil)

      assert_receive {:fallback_message_sent, "Hello from the bot! How can I assist you?"}, 2000
    end
  end
end
