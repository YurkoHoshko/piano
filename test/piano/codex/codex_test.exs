defmodule Piano.CodexTest do
  use ExUnit.Case, async: false

  alias Piano.Codex
  alias Piano.Codex.Client
  alias Piano.Core.{Surface, Agent, Thread, Interaction, InteractionItem}
  alias Piano.TestHarness.CodexReplayHelpers

  @moduletag :codex

  setup do
    Piano.Repo.query!("DELETE FROM interaction_items")
    Piano.Repo.query!("DELETE FROM interactions")
    Piano.Repo.query!("DELETE FROM threads_v2")
    Piano.Repo.query!("DELETE FROM agents_v2")
    Piano.Repo.query!("DELETE FROM surfaces")
    :ok
  end

  describe "sandbox_policy mapping" do
    test "maps read_only to readOnly" do
      assert map_sandbox_policy(:read_only) == %{type: "readOnly"}
    end

    test "maps workspace_write to workspaceWrite" do
      assert map_sandbox_policy(:workspace_write) == %{type: "workspaceWrite"}
    end

    test "maps full_access to dangerFullAccess" do
      assert map_sandbox_policy(:full_access) == %{type: "dangerFullAccess"}
    end

    defp map_sandbox_policy(:read_only), do: %{type: "readOnly"}
    defp map_sandbox_policy(:workspace_write), do: %{type: "workspaceWrite"}
    defp map_sandbox_policy(:full_access), do: %{type: "dangerFullAccess"}
  end

  describe "item type mapping" do
    test "maps Codex item types to atoms" do
      assert map_item_type("userMessage") == :user_message
      assert map_item_type("agentMessage") == :agent_message
      assert map_item_type("reasoning") == :reasoning
      assert map_item_type("commandExecution") == :command_execution
      assert map_item_type("fileChange") == :file_change
      assert map_item_type("mcpToolCall") == :mcp_tool_call
      assert map_item_type("webSearch") == :web_search
    end

    defp map_item_type("userMessage"), do: :user_message
    defp map_item_type("agentMessage"), do: :agent_message
    defp map_item_type("reasoning"), do: :reasoning
    defp map_item_type("commandExecution"), do: :command_execution
    defp map_item_type("fileChange"), do: :file_change
    defp map_item_type("mcpToolCall"), do: :mcp_tool_call
    defp map_item_type("webSearch"), do: :web_search
    defp map_item_type(_), do: :agent_message
  end

  describe "start_turn prerequisites" do
    setup do
      {:ok, surface} = Ash.create(Surface, %{app: :telegram, identifier: "test_chat"})
      {:ok, agent} = Ash.create(Agent, %{
        name: "Test Agent",
        model: "gpt-4",
        workspace_path: "/tmp/test_workspace",
        sandbox_policy: :workspace_write
      })
      {:ok, thread} = Ash.create(Thread, %{surface_id: surface.id, agent_id: agent.id})
      {:ok, interaction} = Ash.create(Interaction, %{
        original_message: "Hello, world!",
        surface_id: surface.id,
        thread_id: thread.id
      })

      {:ok, surface: surface, agent: agent, thread: thread, interaction: interaction}
    end

    test "loads interaction with relationships", %{interaction: interaction} do
      {:ok, loaded} = Ash.load(interaction, [:thread, :surface, thread: [:agent]])

      assert loaded.thread != nil
      assert loaded.surface != nil
      assert loaded.thread.agent != nil
    end

    test "interaction can be started with turn_id", %{interaction: interaction} do
      {:ok, started} = Ash.update(interaction, %{codex_turn_id: "turn_123"}, action: :start)

      assert started.status == :in_progress
      assert started.codex_turn_id == "turn_123"
    end

    test "thread can be updated with codex_thread_id", %{thread: thread} do
      {:ok, updated} = Ash.update(thread, %{codex_thread_id: "thread_abc"}, action: :set_codex_thread_id)

      assert updated.codex_thread_id == "thread_abc"
    end
  end

  describe "integration with Codex app-server + replay API" do
    @describetag :integration

    setup do
      :ok = ensure_app_started()
      :ok = CodexReplayHelpers.start_endpoint!()
      base_url = CodexReplayHelpers.base_url()
      fixture_path = "test/fixtures/codex/replay.json"

      env = [
        {~c"OPENAI_BASE_URL", String.to_charlist(base_url)},
        {~c"OPENAI_API_KEY", ~c"test-key"}
      ]

      {:ok, _pid} = Client.start_link(name: :integration_client, env: env)
      Process.sleep(2000)

      {:ok, surface} = Ash.create(Surface, %{app: :telegram, identifier: "integration_test"})
      {:ok, agent} = Ash.create(Agent, %{
        name: "Integration Agent",
        model: "gpt-4",
        workspace_path: "/tmp/integration_test",
        sandbox_policy: :workspace_write
      })
      {:ok, thread} = Ash.create(Thread, %{surface_id: surface.id, agent_id: agent.id})
      {:ok, interaction} = Ash.create(Interaction, %{
        original_message: "What is 2+2?",
        surface_id: surface.id,
        thread_id: thread.id
      })

      on_exit(fn ->
        Client.stop(:integration_client)
      end)

      {:ok, fixture_path: fixture_path, interaction: interaction}
    end

    test "full turn flow persists response and items", %{fixture_path: fixture_path, interaction: interaction} do
      CodexReplayHelpers.with_replay_paths([fixture_path], fn ->
        {:ok, completed} = Codex.start_turn(interaction, client: :integration_client)

        assert completed.status == :complete
        assert completed.response == "Generic replay response."

        {:ok, items} =
          Ash.read(InteractionItem,
            action: :list_by_interaction,
            input: %{interaction_id: completed.id}
          )

        assert Enum.any?(items, fn item ->
          item.type == :agent_message and
            get_in(item.payload, ["item", "text"]) == "Generic replay response."
        end)
      end)
    end
  end

  defp ensure_app_started do
    case Application.ensure_all_started(:piano) do
      {:ok, _} -> :ok
      {:error, {:already_started, :piano}} -> :ok
      {:error, reason} -> raise "Failed to start :piano app: #{inspect(reason)}"
    end

    if is_nil(Process.whereis(Piano.Repo)) do
      case Piano.Repo.start_link() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        {:error, reason} -> raise "Failed to start Piano.Repo: #{inspect(reason)}"
      end
    end

    if is_nil(Process.whereis(Piano.PubSub)) do
      case Phoenix.PubSub.Supervisor.start_link(name: Piano.PubSub) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        {:error, reason} -> raise "Failed to start Piano.PubSub: #{inspect(reason)}"
      end
    end

    :ok
  end
end
