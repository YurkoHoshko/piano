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
      case :ets.whereis(:piano_pending_requests) do
        :undefined -> :ok
        _ref -> :ets.delete_all_objects(:piano_pending_requests)
      end

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
        {:ok, build_response(@mock_response)}
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
        {:ok, build_response(@mock_response)}
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
      assert content =~ "❌"
    end

    test "falls back to send_message when edit fails", %{agent: _agent} do
      chat_id = 555_666_777
      test_pid = self()
      placeholder_message_id = 123

      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:ok, build_response(@mock_response)}
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

    test "splits long responses across multiple messages", %{agent: _agent} do
      chat_id = 888_999_000
      test_pid = self()
      placeholder_message_id = 456

      long_content = String.duplicate("A", 5000)

      mock_response = %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => long_content
            },
            "finish_reason" => "stop"
          }
        ]
      }

      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:ok, build_response(mock_response)}
      end)

      Piano.Telegram.API.Mock
      |> stub(:send_chat_action, fn _chat_id, "typing", _opts ->
        {:ok, %{}}
      end)
      |> expect(:send_message, fn ^chat_id, "⏳ Processing...", _opts ->
        {:ok, %{message_id: placeholder_message_id}}
      end)
      |> expect(:edit_message_text, fn ^chat_id, ^placeholder_message_id, first_chunk, _opts ->
        send(test_pid, {:first_chunk_edited, byte_size(first_chunk)})
        {:ok, %{}}
      end)
      |> expect(:send_message, fn ^chat_id, second_chunk, _opts ->
        send(test_pid, {:second_chunk_sent, byte_size(second_chunk)})
        {:ok, %{}}
      end)

      mock_msg = %{chat: %{id: chat_id}}

      Bot.handle({:text, "Send me a long response", mock_msg}, nil)

      assert_receive {:first_chunk_edited, first_len}, 2000
      assert first_len <= 4096
      assert_receive {:second_chunk_sent, second_len}, 2000
      assert second_len > 0
    end

    test "appends tool calls and sends drawer", %{agent: _agent} do
      chat_id = 222_333_444
      test_pid = self()
      placeholder_message_id = 4242

      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        caller = self()
        send(test_pid, {:llm_called, caller})

        receive do
          :continue -> :ok
        after
          2_000 -> :ok
        end

        {:ok, build_response(@mock_response)}
      end)

      Piano.Telegram.API.Mock
      |> stub(:send_chat_action, fn _chat_id, "typing", _opts ->
        {:ok, %{}}
      end)
      |> stub(:send_message, fn ^chat_id, text, opts ->
        send(test_pid, {:send_message, text, opts})

        if text == "⏳ Processing..." do
          {:ok, %{message_id: placeholder_message_id}}
        else
          {:ok, %{}}
        end
      end)
      |> stub(:edit_message_text, fn ^chat_id, ^placeholder_message_id, content, _opts ->
        send(test_pid, {:message_edited, content})
        {:ok, %{}}
      end)

      mock_msg = %{chat: %{id: chat_id}}

      Bot.handle({:text, "Show tools", mock_msg}, nil)

      assert_receive {:llm_called, llm_pid}, 2_000

      thread_id = Piano.Telegram.SessionMapper.get_thread(chat_id)
      assert is_binary(thread_id)

      Piano.Events.broadcast(thread_id, {:tool_call, %{name: "bash", arguments: %{"command" => "ls"}}})
      send(llm_pid, :continue)

      edits = collect_message_edits([])
      assert Enum.any?(edits, &String.contains?(&1, "Hello from the bot!"))

      if Enum.any?(edits, &String.contains?(&1, "Tool calls so far")) do
        assert Enum.any?(edits, &String.contains?(&1, "bash(command=ls)"))
      end

      sent_messages = collect_sent_messages([])

      assert Enum.any?(sent_messages, fn {text, _opts} ->
               String.contains?(text, "<spoiler>Tool calls:")
             end)

      assert Enum.any?(sent_messages, fn {text, _opts} ->
               String.contains?(text, "bash(command=ls)")
             end)

      assert Enum.any?(sent_messages, fn {_text, opts} ->
               Keyword.get(opts, :parse_mode) == "HTML"
             end)
    end
  end

  defp build_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    msg = ReqLLM.Context.assistant(content)
    %ReqLLM.Response{
      id: "test-response",
      model: "gpt-oss-20b",
      finish_reason: "stop",
      usage: %{prompt_tokens: 1, completion_tokens: 1, total_tokens: 2},
      message: msg,
      context: ReqLLM.Context.new([msg])
    }
  end

  defp collect_message_edits(edits) do
    receive do
      {:message_edited, content} ->
        collect_message_edits([content | edits])
    after
      500 ->
        Enum.reverse(edits)
    end
  end

  defp collect_sent_messages(messages) do
    receive do
      {:send_message, text, opts} ->
        collect_sent_messages([{text, opts} | messages])
    after
      500 ->
        Enum.reverse(messages)
    end
  end
end
