defmodule Piano.CodexTest do
  use ExUnit.Case, async: false
  require Logger

  alias Piano.Codex
  alias Piano.Codex.Client
  alias Piano.Core.{Thread, Interaction, InteractionItem}
  alias Piano.TestHarness.CodexReplayHelpers
  alias Piano.TestHarness.CodexReplay

  @moduletag :codex

  setup do
    Piano.Repo.query!("DELETE FROM interaction_items")
    Piano.Repo.query!("DELETE FROM interactions")
    Piano.Repo.query!("DELETE FROM threads_v2")
    Piano.Repo.query!("DELETE FROM agents_v2")
    Piano.Repo.query!("DELETE FROM surfaces")
    :ok
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
      reply_to = "telegram:123456:789"
      {:ok, thread} = Ash.create(Thread, %{reply_to: "telegram:123456"})
      {:ok, interaction} = Ash.create(Interaction, %{
        original_message: "Hello, world!",
        reply_to: reply_to,
        thread_id: thread.id
      })

      {:ok, thread: thread, interaction: interaction}
    end

    test "loads interaction with relationships", %{interaction: interaction} do
      {:ok, loaded} = Ash.load(interaction, [:thread, thread: [:agent]])

      assert loaded.thread != nil
      assert loaded.thread.agent == nil
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
      Logger.configure(level: :debug)
      Logger.debug(
        "Codex pipeline status pipeline=#{inspect(Process.whereis(Piano.Pipeline.CodexEventPipeline))} producer=#{inspect(Process.whereis(Piano.Pipeline.CodexEventProducer))}"
      )

      if is_nil(Process.whereis(Piano.Repo)) do
        case Piano.Repo.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} -> raise "Failed to start Piano.Repo: #{inspect(reason)}"
        end
      end

      if is_nil(Process.whereis(Piano.Repo)) do
        raise "Piano.Repo is not running after start attempt"
      end

      if is_nil(Process.whereis(Piano.PubSub)) do
        case Phoenix.PubSub.Supervisor.start_link(name: Piano.PubSub) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} -> raise "Failed to start Piano.PubSub: #{inspect(reason)}"
        end
      end
      :ok = CodexReplayHelpers.start_endpoint!()
      base_url = CodexReplayHelpers.base_url()
      fixture_path = "test/fixtures/codex/replay.json"
      codex_home = Path.expand("tmp/codex_home", File.cwd!())
      File.mkdir_p!(codex_home)
      File.write!(Path.join(codex_home, "config.toml"), codex_config_toml(base_url))

      env = [
        {~c"OPENAI_BASE_URL", String.to_charlist(base_url)},
        {~c"OPENAI_API_KEY", ~c"test-key"},
        {~c"CODEX_HOME", String.to_charlist(codex_home)}
      ]

      {:ok, _pid} = Client.start_link(name: :integration_client, env: env)
      Process.sleep(2000)

      :ok = CodexReplay.clear_last_request()

      reply_to = "telegram:123456:789"
      {:ok, thread} = Ash.create(Thread, %{reply_to: "telegram:123456"})
      {:ok, interaction} = Ash.create(Interaction, %{
        original_message: "What is 2+2?",
        reply_to: reply_to,
        thread_id: thread.id
      })

      on_exit(fn ->
        if Process.whereis(:integration_client) do
          Client.stop(:integration_client)
        end
      end)

      {:ok, fixture_path: fixture_path, interaction: interaction}
    end

    test "full turn flow persists response and items", %{fixture_path: fixture_path, interaction: interaction} do
      CodexReplayHelpers.with_replay_paths([fixture_path], fn ->
        {:ok, started} = Codex.start_turn(interaction, client: :integration_client)
        {:ok, _request} = await_replay_request()
        {:ok, completed} = await_completion(started.id)

        assert completed.status == :complete
        assert completed.response == "Generic replay response."

        query = Ash.Query.for_read(InteractionItem, :list_by_interaction, %{interaction_id: completed.id})
        {:ok, items} = Ash.read(query)

        assert Enum.any?(items, fn item ->
          item.type == :agent_message and
            get_in(item.payload, ["item", "text"]) == "Generic replay response."
        end)
      end)
    end
  end

  defp await_completion(interaction_id) do
    await_completion(interaction_id, 50)
  end

  defp codex_config_toml(base_url) do
    """
    sandbox_mode = "workspace-write"

    model = "gpt-4"
    model_provider = "openai"

    [model_providers.openai]
    name = "OpenAI"
    base_url = "#{base_url}"
    env_key = "OPENAI_API_KEY"
    wire_api = "responses"

    [profiles.replay]
    model = "gpt-4"
    model_provider = "openai"

    [sandbox_workspace_write]
    network_access = true
    """
  end

  defp await_replay_request do
    await_replay_request(50)
  end

  defp await_replay_request(0), do: {:error, :timeout}

  defp await_replay_request(attempts) do
    case CodexReplay.last_request() do
      nil ->
        Process.sleep(100)
        await_replay_request(attempts - 1)

      request ->
        {:ok, request}
    end
  end

  defp await_completion(_interaction_id, 0), do: {:error, :timeout}

  defp await_completion(interaction_id, attempts) do
    case Ash.get(Interaction, interaction_id) do
      {:ok, %{status: :complete} = interaction} ->
        {:ok, interaction}

      {:ok, _} ->
        Process.sleep(100)
        await_completion(interaction_id, attempts - 1)

      {:error, _} = error ->
        error
    end
  end
end
