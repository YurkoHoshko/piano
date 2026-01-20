defmodule Piano.Chat.ThreadTest do
  use Piano.DataCase, async: false

  alias Piano.Chat.{Thread, Message}

  describe "create action" do
    test "creates thread with default status" do
      assert {:ok, thread} = Ash.create(Thread, %{}, action: :create)
      assert thread.status == :active
      assert thread.title == nil
    end

    test "creates thread with title" do
      assert {:ok, thread} = Ash.create(Thread, %{title: "Test Thread"}, action: :create)
      assert thread.title == "Test Thread"
    end
  end

  describe "list action" do
    test "returns threads sorted by inserted_at desc" do
      {:ok, thread1} = Ash.create(Thread, %{title: "First"}, action: :create)
      Process.sleep(10)
      {:ok, thread2} = Ash.create(Thread, %{title: "Second"}, action: :create)

      {:ok, threads} = Ash.read(Thread, action: :list)

      assert length(threads) >= 2
      ids = Enum.map(threads, & &1.id)
      assert Enum.find_index(ids, &(&1 == thread2.id)) < Enum.find_index(ids, &(&1 == thread1.id))
    end
  end

  describe "archive action" do
    test "archives a thread" do
      {:ok, thread} = Ash.create(Thread, %{title: "To Archive"}, action: :create)
      assert thread.status == :active

      {:ok, archived} = Ash.update(thread, %{}, action: :archive)
      assert archived.status == :archived
    end
  end

  describe "fork action" do
    test "forks a thread with messages up to fork point" do
      {:ok, source} = Ash.create(Thread, %{title: "Source Thread"}, action: :create)

      {:ok, _msg1} = Ash.create(Message, %{
        content: "Message 1",
        role: :user,
        source: :web,
        thread_id: source.id
      }, action: :create)

      Process.sleep(10)

      {:ok, msg2} = Ash.create(Message, %{
        content: "Message 2",
        role: :agent,
        source: :web,
        thread_id: source.id
      }, action: :create)

      Process.sleep(10)

      {:ok, _msg3} = Ash.create(Message, %{
        content: "Message 3",
        role: :user,
        source: :web,
        thread_id: source.id
      }, action: :create)

      {:ok, forked} = Ash.create(Thread, %{
        source_thread_id: source.id,
        fork_at_message_id: msg2.id
      }, action: :fork)

      assert forked.title == "Fork of Source Thread"
      assert forked.forked_from_thread_id == source.id
      assert forked.forked_from_message_id == msg2.id

      query = Ash.Query.for_read(Message, :list_by_thread, %{thread_id: forked.id})
      {:ok, forked_messages} = Ash.read(query)

      assert length(forked_messages) == 2
      contents = Enum.map(forked_messages, & &1.content)
      assert "Message 1" in contents
      assert "Message 2" in contents
      refute "Message 3" in contents
    end
  end
end
