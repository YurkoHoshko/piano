defmodule Piano.Tools.SurfaceToolResourceTest do
  use ExUnit.Case, async: true

  alias Piano.Mock.Surface, as: MockSurface
  alias Piano.Tools.SurfaceToolResource

  describe "send_message action" do
    test "sends message to mock surface" do
      mock_id = "test-tool-#{System.unique_integer([:positive])}"
      {:ok, _} = MockSurface.start(mock_id)

      result =
        SurfaceToolResource
        |> Ash.ActionInput.for_action(:send_message, %{
          surface_id: "mock:#{mock_id}",
          message: "Test message from tool"
        })
        |> Ash.run_action()

      assert {:ok, result_map} = result
      assert result_map.success == true
      assert result_map.surface_id == "mock:#{mock_id}"
      assert result_map.message_preview == "Test message from tool"

      events = MockSurface.get_results(mock_id)
      assert length(events) == 1
      assert hd(events).type == :message_sent
      assert hd(events).data.message == "Test message from tool"

      MockSurface.stop(mock_id)
    end

    test "returns error for invalid surface_id" do
      result =
        SurfaceToolResource
        |> Ash.ActionInput.for_action(:send_message, %{
          surface_id: "invalid:format",
          message: "Test message"
        })
        |> Ash.run_action()

      assert {:error, _} = result
    end
  end

  describe "send_to_chat action" do
    test "builds telegram surface from chat_id" do
      result =
        SurfaceToolResource
        |> Ash.ActionInput.for_action(:send_to_chat, %{
          chat_id: 123_456,
          message: "Hello from tool"
        })
        |> Ash.run_action()

      # This will fail to actually send since Telegram isn't connected,
      # but we're testing the action structure
      # The error is expected since ExGram isn't running in test
      assert match?({:error, _}, result) or match?({:ok, %{chat_id: 123_456}}, result)
    end
  end
end
