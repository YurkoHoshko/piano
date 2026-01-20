defmodule Piano.Agents.AgentTest do
  use Piano.DataCase, async: false

  alias Piano.Agents.Agent

  describe "create action" do
    test "creates agent with required fields" do
      assert {:ok, agent} = Ash.create(Agent, %{
        name: "Test Agent",
        model: "qwen3:32b"
      }, action: :create)

      assert agent.name == "Test Agent"
      assert agent.model == "qwen3:32b"
      assert agent.enabled_tools == []
      assert agent.enabled_skills == []
    end

    test "creates agent with all fields" do
      assert {:ok, agent} = Ash.create(Agent, %{
        name: "Full Agent",
        description: "A test agent",
        model: "gpt-4",
        system_prompt: "You are helpful",
        enabled_tools: ["read_file", "write_file"],
        enabled_skills: ["coding", "research"]
      }, action: :create)

      assert agent.description == "A test agent"
      assert agent.system_prompt == "You are helpful"
      assert agent.enabled_tools == ["read_file", "write_file"]
      assert agent.enabled_skills == ["coding", "research"]
    end

    test "fails without name" do
      assert {:error, _} = Ash.create(Agent, %{
        model: "gpt-4"
      }, action: :create)
    end

    test "fails without model" do
      assert {:error, _} = Ash.create(Agent, %{
        name: "Test Agent"
      }, action: :create)
    end
  end

  describe "list action" do
    test "returns agents sorted by inserted_at asc" do
      {:ok, agent1} = Ash.create(Agent, %{name: "First", model: "m1"}, action: :create)
      Process.sleep(10)
      {:ok, agent2} = Ash.create(Agent, %{name: "Second", model: "m2"}, action: :create)

      {:ok, agents} = Ash.read(Agent, action: :list)

      ids = Enum.map(agents, & &1.id)
      assert Enum.find_index(ids, &(&1 == agent1.id)) < Enum.find_index(ids, &(&1 == agent2.id))
    end
  end

  describe "update_config action" do
    test "updates enabled_tools and enabled_skills" do
      {:ok, agent} = Ash.create(Agent, %{
        name: "Updatable",
        model: "test"
      }, action: :create)

      assert agent.enabled_tools == []
      assert agent.enabled_skills == []

      {:ok, updated} = Ash.update(agent, %{
        enabled_tools: ["tool1", "tool2"],
        enabled_skills: ["skill1"]
      }, action: :update_config)

      assert updated.enabled_tools == ["tool1", "tool2"]
      assert updated.enabled_skills == ["skill1"]
    end

    test "updates name and model" do
      {:ok, agent} = Ash.create(Agent, %{
        name: "Original",
        model: "old-model"
      }, action: :create)

      {:ok, updated} = Ash.update(agent, %{
        name: "Updated Name",
        model: "new-model"
      }, action: :update_config)

      assert updated.name == "Updated Name"
      assert updated.model == "new-model"
    end
  end
end
