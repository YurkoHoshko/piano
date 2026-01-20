defmodule Piano.ChatFlowTest do
  use Piano.DataCase, async: false

  import Mox

  alias Piano.Agents.Agent
  alias Piano.Chat.{Message, Thread}
  alias Piano.{ChatGateway, Events}

  setup :set_mox_global
  setup :verify_on_exit!

  @mock_response %{
    "choices" => [
      %{
        "message" => %{
          "role" => "assistant",
          "content" => "Hello! I'm your AI assistant. How can I help you today?"
        },
        "finish_reason" => "stop"
      }
    ]
  }

  describe "web chat flow" do
    setup do
      {:ok, agent} =
        Ash.create(Agent,
          %{
            name: "Test Agent",
            model: "test-model",
            system_prompt: "You are a helpful assistant."
          },
          action: :create
        )

      %{agent: agent}
    end

    test "creates thread, sends message, receives agent response", %{agent: agent} do
      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:ok, build_response(@mock_response)}
      end)

      {:ok, user_message} =
        ChatGateway.handle_incoming("Hello", :web, %{agent_id: agent.id})

      assert user_message.content == "Hello"
      assert user_message.role == :user
      assert user_message.source == :web

      {:ok, thread} = Ash.get(Thread, user_message.thread_id)
      assert thread != nil

      Events.subscribe(thread.id)

      Process.sleep(500)

      query = Ash.Query.for_read(Message, :list_by_thread, %{thread_id: thread.id})
      {:ok, messages} = Ash.read(query)

      user_messages = Enum.filter(messages, &(&1.role == :user))
      agent_messages = Enum.filter(messages, &(&1.role == :agent))

      assert length(user_messages) == 1
      assert length(agent_messages) == 1

      [agent_message] = agent_messages
      assert agent_message.content == "Hello! I'm your AI assistant. How can I help you today?"
      assert agent_message.agent_id == agent.id
    end

    test "broadcasts PubSub events during processing", %{agent: agent} do
      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:ok, build_response(@mock_response)}
      end)

      {:ok, user_message} =
        ChatGateway.handle_incoming("Test message", :web, %{agent_id: agent.id})

      {:ok, thread} = Ash.get(Thread, user_message.thread_id)

      Events.subscribe(thread.id)

      Process.sleep(500)

      receive do
        {:processing_started, message_id} ->
          assert message_id == user_message.id
      after
        0 -> :ok
      end

      receive do
        {:response_ready, agent_message} ->
          assert agent_message.role == :agent
          assert agent_message.content =~ "AI assistant"
      after
        0 -> :ok
      end
    end

    test "stores messages in database correctly", %{agent: agent} do
      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:ok, build_response(@mock_response)}
      end)

      {:ok, user_message} =
        ChatGateway.handle_incoming("Database test", :web, %{agent_id: agent.id})

      Process.sleep(500)

      {:ok, db_user_message} = Ash.get(Message, user_message.id)
      assert db_user_message.content == "Database test"
      assert db_user_message.role == :user
      assert db_user_message.thread_id != nil

      query = Ash.Query.for_read(Message, :list_by_thread, %{thread_id: user_message.thread_id})
      {:ok, all_messages} = Ash.read(query)

      assert length(all_messages) == 2

      agent_msg = Enum.find(all_messages, &(&1.role == :agent))
      assert agent_msg != nil
      assert agent_msg.content == "Hello! I'm your AI assistant. How can I help you today?"
    end
  end

  defp build_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    msg = ReqLLM.Context.assistant(content)
    %ReqLLM.Response{message: msg, context: ReqLLM.Context.new([msg])}
  end
end
