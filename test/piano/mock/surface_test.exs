defmodule Piano.Mock.SurfaceTest do
  use ExUnit.Case, async: true

  alias Piano.Mock.Surface, as: MockSurface
  alias Piano.Surface.Context

  describe "start/1 and stop/1" do
    test "starts and stops a mock surface agent" do
      mock_id = "test-#{System.unique_integer([:positive])}"

      assert {:ok, %MockSurface{mock_id: ^mock_id}} = MockSurface.start(mock_id)
      assert MockSurface.exists?(mock_id)

      assert :ok = MockSurface.stop(mock_id)
      refute MockSurface.exists?(mock_id)
    end

    test "returns existing surface if already started" do
      mock_id = "test-#{System.unique_integer([:positive])}"

      {:ok, surface1} = MockSurface.start(mock_id)
      {:ok, surface2} = MockSurface.start(mock_id)

      assert surface1.mock_id == surface2.mock_id

      MockSurface.stop(mock_id)
    end
  end

  describe "parse/1" do
    test "parses mock:id format" do
      assert {:ok, %MockSurface{mock_id: "test-123"}} = MockSurface.parse("mock:test-123")
    end

    test "parses mock:uuid format" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert {:ok, %MockSurface{mock_id: ^uuid}} = MockSurface.parse("mock:#{uuid}")
    end

    test "returns error for non-mock formats" do
      assert :error = MockSurface.parse("telegram:123:456")
      assert :error = MockSurface.parse("liveview:session")
      assert :error = MockSurface.parse("unknown:foo")
    end
  end

  describe "build_reply_to/1" do
    test "builds mock:id reply_to string" do
      assert "mock:test-123" = MockSurface.build_reply_to("test-123")
    end
  end

  describe "get_results/1 and clear/1" do
    test "returns empty list when no events recorded" do
      mock_id = "test-#{System.unique_integer([:positive])}"
      {:ok, _} = MockSurface.start(mock_id)

      assert [] = MockSurface.get_results(mock_id)

      MockSurface.stop(mock_id)
    end

    test "returns empty list when surface not started" do
      assert [] = MockSurface.get_results("nonexistent-surface")
    end

    test "clears recorded events" do
      mock_id = "test-#{System.unique_integer([:positive])}"
      {:ok, _} = MockSurface.start(mock_id)

      MockSurface.record_event(mock_id, :test_event, %{foo: "bar"})
      assert [_] = MockSurface.get_results(mock_id)

      MockSurface.clear(mock_id)
      assert [] = MockSurface.get_results(mock_id)

      MockSurface.stop(mock_id)
    end
  end

  describe "Piano.Surface protocol implementation" do
    test "collects surface events" do
      mock_id = "test-#{System.unique_integer([:positive])}"
      {:ok, surface} = MockSurface.start(mock_id)

      context = %Context{
        interaction: nil,
        turn_id: "turn-123",
        thread_id: "thread-456"
      }

      assert {:ok, :recorded} = Piano.Surface.on_turn_started(surface, context, %{})
      assert {:ok, :recorded} = Piano.Surface.on_item_completed(surface, context, %{item: %{type: "message"}})
      assert {:ok, :recorded} = Piano.Surface.on_turn_completed(surface, context, %{})

      results = MockSurface.get_results(mock_id)

      assert length(results) == 3
      assert Enum.map(results, & &1.type) == [:turn_started, :item_completed, :turn_completed]

      [turn_started | _] = results
      assert turn_started.data.context == context
      assert %DateTime{} = turn_started.timestamp

      MockSurface.stop(mock_id)
    end

    test "records all lifecycle events" do
      mock_id = "test-#{System.unique_integer([:positive])}"
      {:ok, surface} = MockSurface.start(mock_id)

      context = %Context{interaction: nil, turn_id: "t1", thread_id: "th1"}

      Piano.Surface.on_turn_started(surface, context, %{})
      Piano.Surface.on_item_started(surface, context, %{})
      Piano.Surface.on_agent_message_delta(surface, context, %{delta: "hello"})
      Piano.Surface.on_item_completed(surface, context, %{})
      Piano.Surface.on_approval_required(surface, context, %{type: "file"})
      Piano.Surface.on_turn_completed(surface, context, %{})

      results = MockSurface.get_results(mock_id)
      types = Enum.map(results, & &1.type)

      assert :turn_started in types
      assert :item_started in types
      assert :agent_message_delta in types
      assert :item_completed in types
      assert :approval_required in types
      assert :turn_completed in types

      MockSurface.stop(mock_id)
    end

    test "send_message records message_sent event" do
      mock_id = "test-#{System.unique_integer([:positive])}"
      {:ok, surface} = MockSurface.start(mock_id)

      message = "## Task Complete\n\nYour background task finished!"
      assert {:ok, :recorded} = Piano.Surface.send_message(surface, message)

      results = MockSurface.get_results(mock_id)
      assert [event] = results
      assert event.type == :message_sent
      assert event.data.message == message

      MockSurface.stop(mock_id)
    end
  end
end
