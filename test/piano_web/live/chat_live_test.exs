defmodule PianoWeb.ChatLiveTest do
  use PianoWeb.ConnCase, async: false

  import Mox

  alias Piano.Agents.Agent
  alias Piano.Chat.Thread

  setup :set_mox_global
  setup :verify_on_exit!

  @mock_response %{
    "choices" => [
      %{
        "message" => %{
          "role" => "assistant",
          "content" => "Hello! I'm your AI assistant."
        },
        "finish_reason" => "stop"
      }
    ]
  }

  describe "chat interface" do
    setup do
      {:ok, agent} =
        Ash.create(Agent, %{
          name: "Test Agent",
          model: "test-model",
          system_prompt: "You are helpful."
        }, action: :create)

      %{agent: agent}
    end

    test "user can send message and see it appear", %{conn: conn} do
      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:ok, @mock_response}
      end)

      {:ok, view, _html} = live(conn, "/chat")

      assert has_element?(view, "[data-testid='message-input']")

      view
      |> form("[data-testid='message-form']", %{message: "Hello world"})
      |> render_submit()

      assert has_element?(view, "[data-testid='message-user']")
      assert render(view) =~ "Hello world"

      Process.sleep(500)

      assert has_element?(view, "[data-testid='message-agent']")
      assert render(view) =~ "Hello!"
      assert render(view) =~ "your AI assistant."
    end

    test "user can create new thread via button", %{conn: conn} do
      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        {:ok, @mock_response}
      end)

      {:ok, view, _html} = live(conn, "/chat")

      view
      |> form("[data-testid='message-form']", %{message: "First message"})
      |> render_submit()

      assert has_element?(view, "[data-testid='message-user']")

      Process.sleep(500)

      view
      |> element("[data-testid='new-thread-btn']")
      |> render_click()

      refute has_element?(view, "[data-testid='message-user']")
      assert render(view) =~ "Start a new conversation"
    end

    test "user can switch between threads in sidebar", %{conn: conn} do
      {:ok, thread1} = Ash.create(Thread, %{title: "Thread One"}, action: :create)
      {:ok, thread2} = Ash.create(Thread, %{title: "Thread Two"}, action: :create)

      {:ok, view, _html} = live(conn, "/chat")

      assert render(view) =~ "Thread One"
      assert render(view) =~ "Thread Two"

      view
      |> element("[data-testid='thread-#{thread1.id}']")
      |> render_click()

      view
      |> element("[data-testid='thread-#{thread2.id}']")
      |> render_click()
    end

    test "thinking indicator appears while waiting", %{conn: conn} do
      test_pid = self()

      Piano.LLM.Mock
      |> expect(:complete, fn _messages, _tools, _opts ->
        send(test_pid, :llm_called)
        Process.sleep(200)
        {:ok, @mock_response}
      end)

      {:ok, view, _html} = live(conn, "/chat")

      view
      |> form("[data-testid='message-form']", %{message: "Wait for thinking"})
      |> render_submit()

      assert_receive :llm_called, 2000

      assert has_element?(view, "[data-testid='thinking-indicator']")

      Process.sleep(500)

      refute has_element?(view, "[data-testid='thinking-indicator']")
      assert has_element?(view, "[data-testid='message-agent']")
    end
  end
end
