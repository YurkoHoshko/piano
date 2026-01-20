defmodule Piano.Chat.MessageTest do
  use Piano.DataCase, async: false

  alias Piano.Chat.{Thread, Message}

  setup do
    {:ok, thread} = Ash.create(Thread, %{title: "Test Thread"}, action: :create)
    {:ok, thread: thread}
  end

  describe "create action" do
    test "creates message with required fields", %{thread: thread} do
      assert {:ok, msg} = Ash.create(Message, %{
        content: "Hello, world!",
        role: :user,
        source: :web,
        thread_id: thread.id
      }, action: :create)

      assert msg.content == "Hello, world!"
      assert msg.role == :user
      assert msg.source == :web
      assert msg.thread_id == thread.id
    end

    test "creates agent message", %{thread: thread} do
      assert {:ok, msg} = Ash.create(Message, %{
        content: "I'm an agent response",
        role: :agent,
        source: :telegram,
        thread_id: thread.id
      }, action: :create)

      assert msg.role == :agent
      assert msg.source == :telegram
    end

    test "fails without content", %{thread: thread} do
      assert {:error, _} = Ash.create(Message, %{
        role: :user,
        source: :web,
        thread_id: thread.id
      }, action: :create)
    end

    test "fails with invalid role", %{thread: thread} do
      assert {:error, _} = Ash.create(Message, %{
        content: "Test",
        role: :invalid_role,
        source: :web,
        thread_id: thread.id
      }, action: :create)
    end

    test "fails with invalid source", %{thread: thread} do
      assert {:error, _} = Ash.create(Message, %{
        content: "Test",
        role: :user,
        source: :invalid_source,
        thread_id: thread.id
      }, action: :create)
    end
  end

  describe "list_by_thread action" do
    test "returns messages for correct thread only", %{thread: thread} do
      {:ok, other_thread} = Ash.create(Thread, %{title: "Other"}, action: :create)

      {:ok, msg1} = Ash.create(Message, %{
        content: "In thread",
        role: :user,
        source: :web,
        thread_id: thread.id
      }, action: :create)

      {:ok, _msg2} = Ash.create(Message, %{
        content: "In other",
        role: :user,
        source: :web,
        thread_id: other_thread.id
      }, action: :create)

      query = Ash.Query.for_read(Message, :list_by_thread, %{thread_id: thread.id})
      {:ok, messages} = Ash.read(query)

      assert length(messages) == 1
      assert hd(messages).id == msg1.id
    end

    test "returns empty list for thread with no messages" do
      {:ok, empty_thread} = Ash.create(Thread, %{title: "Empty"}, action: :create)

      query = Ash.Query.for_read(Message, :list_by_thread, %{thread_id: empty_thread.id})
      {:ok, messages} = Ash.read(query)

      assert messages == []
    end
  end
end
