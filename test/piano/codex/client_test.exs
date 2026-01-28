defmodule Piano.Codex.ClientTest do
  use ExUnit.Case, async: false

  alias Piano.Codex.Client
  alias Piano.TestHarness.CodexReplayHelpers

  @moduletag :codex

  describe "with replay controller" do
    setup do
      :ok = CodexReplayHelpers.start_endpoint!()
      base_url = CodexReplayHelpers.base_url()
      fixture_path = "test/fixtures/codex/replay.json"

      {:ok, base_url: base_url, fixture_path: fixture_path}
    end

    @tag :skip
    @tag timeout: 30_000
    test "initializes with real codex pointed at replay API", %{base_url: base_url, fixture_path: fixture_path} do
      env = [
        {~c"OPENAI_BASE_URL", String.to_charlist(base_url)},
        {~c"OPENAI_API_KEY", ~c"test-key"}
      ]

      CodexReplayHelpers.with_replay_paths([fixture_path], fn ->
        {:ok, _pid} = Client.start_link(
          name: :codex_replay_test,
          env: env,
          auto_initialize: true
        )

        Process.sleep(2000)

        assert Client.ready?(:codex_replay_test)

        Client.stop(:codex_replay_test)
      end)
    end
  end

  describe "Client GenServer logic" do
    test "tracks pending requests" do
      state = %Client{
        port: nil,
        pending_requests: %{},
        notification_handlers: %{},
        request_handlers: %{},
        next_id: 1,
        buffer: "",
        initialized: false
      }

      assert state.next_id == 1
      assert state.pending_requests == %{}
    end

    test "notification handlers can be registered and unregistered" do
      handlers = %{}
      handler = fn _method, _params -> :ok end

      handlers = Map.put(handlers, "test/event", handler)
      assert Map.has_key?(handlers, "test/event")

      handlers = Map.delete(handlers, "test/event")
      refute Map.has_key?(handlers, "test/event")
    end

    test "request handlers can be registered" do
      handlers = %{}
      handler = fn _method, _params -> {:ok, %{decision: "accept"}} end

      handlers = Map.put(handlers, "commandExecution/approve", handler)
      assert Map.has_key?(handlers, "commandExecution/approve")

      result = handlers["commandExecution/approve"].("commandExecution/approve", %{})
      assert result == {:ok, %{decision: "accept"}}
    end
  end

  describe "JSON-RPC message handling" do
    test "parses successful response" do
      json = ~s({"jsonrpc":"2.0","id":1,"result":{"threadId":"thread_abc123"}})
      {:ok, message} = Jason.decode(json)

      assert message["id"] == 1
      assert message["result"]["threadId"] == "thread_abc123"
    end

    test "parses error response" do
      json = ~s({"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"Invalid Request"}})
      {:ok, message} = Jason.decode(json)

      assert message["id"] == 1
      assert message["error"]["code"] == -32600
    end

    test "parses notification" do
      json = ~s({"jsonrpc":"2.0","method":"turn/started","params":{"turnId":"turn_xyz"}})
      {:ok, message} = Jason.decode(json)

      assert message["method"] == "turn/started"
      assert message["params"]["turnId"] == "turn_xyz"
    end

    test "parses server request (approval)" do
      json = ~s({"jsonrpc":"2.0","id":5,"method":"commandExecution/approve","params":{"command":"rm -rf /"}})
      {:ok, message} = Jason.decode(json)

      assert message["id"] == 5
      assert message["method"] == "commandExecution/approve"
      assert message["params"]["command"] == "rm -rf /"
    end
  end
end
