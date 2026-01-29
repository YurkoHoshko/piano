defmodule Piano.CoreTest do
  use ExUnit.Case, async: false

  alias Piano.Core.{Surface, Agent, Thread, Interaction, InteractionItem}

  setup do
    Piano.Repo.query!("DELETE FROM interaction_items")
    Piano.Repo.query!("DELETE FROM interactions")
    Piano.Repo.query!("DELETE FROM threads_v2")
    Piano.Repo.query!("DELETE FROM agents_v2")
    Piano.Repo.query!("DELETE FROM surfaces")
    :ok
  end

  describe "Surface" do
    test "creates a surface with valid attributes" do
      assert {:ok, surface} =
               Ash.create(Surface, %{app: :telegram, identifier: "123456", config: %{foo: "bar"}})

      assert surface.app == :telegram
      assert surface.identifier == "123456"
      assert surface.config == %{"foo" => "bar"}
    end

    test "get_by_app_and_identifier finds existing surface" do
      {:ok, created} = Ash.create(Surface, %{app: :telegram, identifier: "test123"})

      query = Ash.Query.for_read(Surface, :get_by_app_and_identifier, %{app: :telegram, identifier: "test123"})
      {:ok, found} = Ash.read_one(query)

      assert found.id == created.id
    end

    test "upserts on duplicate app+identifier" do
      {:ok, first} = Ash.create(Surface, %{app: :telegram, identifier: "same", config: %{v: 1}})
      {:ok, second} = Ash.create(Surface, %{app: :telegram, identifier: "same", config: %{v: 2}})

      assert first.id == second.id
      assert second.config == %{"v" => 2}
    end
  end

  describe "Agent" do
    test "creates an agent with valid attributes" do
      assert {:ok, agent} =
               Ash.create(Agent, %{
                 name: "Test Agent",
                 model: "o3",
                 workspace_path: "/tmp/agent1"
               })

      assert agent.name == "Test Agent"
      assert agent.model == "o3"
      assert agent.sandbox_policy == :workspace_write
      assert agent.auto_approve_policy == :none
    end

    test "get_default returns agent marked as default" do
      {:ok, _} = Ash.create(Agent, %{name: "Regular", model: "o3", workspace_path: "/tmp/a"})
      {:ok, default} = Ash.create(Agent, %{name: "Default", model: "o3", workspace_path: "/tmp/b", is_default: true})

      query = Ash.Query.for_read(Agent, :get_default)
      {:ok, found} = Ash.read_one(query)

      assert found.id == default.id
    end
  end

  describe "Thread" do
    test "creates a thread with reply_to and agent" do
      {:ok, agent} = Ash.create(Agent, %{name: "Agent", model: "o3", workspace_path: "/tmp"})

      {:ok, thread} = Ash.create(Thread, %{reply_to: "telegram:123456", agent_id: agent.id})

      assert thread.status == :active
      assert thread.reply_to == "telegram:123456"
      assert thread.agent_id == agent.id
    end

    test "find_recent_for_reply_to finds active thread updated recently" do
      {:ok, thread} = Ash.create(Thread, %{reply_to: "telegram:123456:789"})

      query = Ash.Query.for_read(Thread, :find_recent_for_reply_to, %{reply_to: "telegram:123456:999"})
      {:ok, results} = Ash.read(query)

      assert length(results) == 1
      assert hd(results).id == thread.id
    end

    test "archive changes status to archived" do
      {:ok, thread} = Ash.create(Thread, %{reply_to: "telegram:123456"})

      {:ok, archived} = Ash.update(thread, %{}, action: :archive)

      assert archived.status == :archived
    end
  end

  describe "Interaction" do
    test "creates an interaction with reply_to" do
      {:ok, interaction} =
        Ash.create(Interaction, %{
          original_message: "Hello!",
          reply_to: "telegram:123456:789"
        })

      assert interaction.original_message == "Hello!"
      assert interaction.status == :pending
      assert interaction.reply_to == "telegram:123456:789"
    end

    test "transitions through status lifecycle" do
      {:ok, interaction} = Ash.create(Interaction, %{original_message: "Test", reply_to: "telegram:1:2"})

      {:ok, started} = Ash.update(interaction, %{codex_turn_id: "turn_123"}, action: :start)
      assert started.status == :in_progress
      assert started.codex_turn_id == "turn_123"

      {:ok, completed} = Ash.update(started, %{response: "Hello back!"}, action: :complete)
      assert completed.status == :complete
      assert completed.response == "Hello back!"
    end

    test "can assign thread after creation" do
      {:ok, thread} = Ash.create(Thread, %{reply_to: "telegram:1"})
      {:ok, interaction} = Ash.create(Interaction, %{original_message: "Hi", reply_to: "telegram:1:99"})

      {:ok, assigned} = Ash.update(interaction, %{thread_id: thread.id}, action: :assign_thread)

      assert assigned.thread_id == thread.id
    end
  end

  describe "InteractionItem" do
    test "creates an item for an interaction" do
      {:ok, interaction} = Ash.create(Interaction, %{original_message: "Hi", reply_to: "telegram:1:2"})

      {:ok, item} =
        Ash.create(InteractionItem, %{
          codex_item_id: "item_abc",
          type: :agent_message,
          payload: %{text: "Hello!"},
          interaction_id: interaction.id
        })

      assert item.codex_item_id == "item_abc"
      assert item.type == :agent_message
      assert item.status == :started
    end

    test "complete updates status" do
      {:ok, interaction} = Ash.create(Interaction, %{original_message: "Hi", reply_to: "telegram:1:2"})
      {:ok, item} = Ash.create(InteractionItem, %{codex_item_id: "x", type: :agent_message, interaction_id: interaction.id})

      {:ok, completed} = Ash.update(item, %{}, action: :complete)

      assert completed.status == :completed
    end

    test "list_by_interaction returns items for interaction" do
      {:ok, interaction} = Ash.create(Interaction, %{original_message: "Hi", reply_to: "telegram:1:2"})
      {:ok, _} = Ash.create(InteractionItem, %{codex_item_id: "1", type: :user_message, interaction_id: interaction.id})
      {:ok, _} = Ash.create(InteractionItem, %{codex_item_id: "2", type: :agent_message, interaction_id: interaction.id})

      query = Ash.Query.for_read(InteractionItem, :list_by_interaction, %{interaction_id: interaction.id})
      {:ok, items} = Ash.read(query)

      assert length(items) == 2
    end
  end
end
