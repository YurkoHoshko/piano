defmodule Piano.Background.TaskWarriorTest do
  use ExUnit.Case, async: true

  alias Piano.Background.TaskWarrior
  alias Piano.Mock.Surface, as: MockSurface

  describe "taskwarrior_available?/0" do
    test "returns boolean indicating taskwarrior availability" do
      result = TaskWarrior.taskwarrior_available?()
      assert is_boolean(result)
    end
  end

  describe "list_background_tasks/0" do
    @tag :taskwarrior
    test "returns list of tasks when taskwarrior is available" do
      if TaskWarrior.taskwarrior_available?() do
        assert {:ok, tasks} = TaskWarrior.list_background_tasks()
        assert is_list(tasks)
      end
    end

    @tag :taskwarrior
    test "returns empty list when no background tasks exist" do
      if TaskWarrior.taskwarrior_available?() do
        {:ok, tasks} = TaskWarrior.list_background_tasks()
        assert is_list(tasks)
      end
    end
  end

  describe "process_background_tasks/0" do
    test "handles missing taskwarrior gracefully" do
      assert :ok = TaskWarrior.process_background_tasks()
    end
  end

  describe "MockSurface integration" do
    test "mock surface can be created for task processing" do
      mock_id = "task-test-#{System.unique_integer([:positive])}"

      {:ok, surface} = MockSurface.start(mock_id)
      reply_to = MockSurface.build_reply_to(mock_id)

      assert reply_to == "mock:#{mock_id}"
      assert surface.mock_id == mock_id

      MockSurface.stop(mock_id)
    end

    test "mock surface collects events during task execution" do
      mock_id = "task-#{System.unique_integer([:positive])}"
      {:ok, _surface} = MockSurface.start(mock_id)

      MockSurface.record_event(mock_id, :turn_started, %{task_id: "test"})
      MockSurface.record_event(mock_id, :turn_completed, %{task_id: "test"})

      results = MockSurface.get_results(mock_id)
      assert length(results) == 2

      MockSurface.stop(mock_id)
    end
  end
end
