defmodule Piano.Agents.ToolRegistryTest do
  use ExUnit.Case, async: false

  alias Piano.Agents.ToolRegistry
  alias Piano.Agents.SkillRegistry

  @fixtures_dir "test/fixtures/.piano/skills"

  setup do
    # Ensure SkillRegistry ETS table exists
    if :ets.info(:piano_skills) != :undefined do
      :ets.delete(:piano_skills)
    end

    SkillRegistry.init()

    :ok
  end

  describe "load_skill tool" do
    test "list_available/0 includes load_skill" do
      assert "load_skill" in ToolRegistry.list_available()
    end

    test "execute_load_skill/1 returns skill content when skill exists" do
      skill_path = Path.join(@fixtures_dir, "test-skill/SKILL.md")

      skill = %{
        name: "test-skill",
        description: "A test skill",
        path: skill_path
      }

      :ets.insert(:piano_skills, {skill.name, skill})

      assert {:ok, content} = ToolRegistry.execute_load_skill(%{name: "test-skill"})
      assert content =~ "# Test Skill"
      assert content =~ "name: test-skill"
    end

    test "execute_load_skill/1 returns error when skill not found" do
      assert {:error, "Skill not found: non-existent"} =
               ToolRegistry.execute_load_skill(%{name: "non-existent"})
    end

    test "execute_load_skill/1 returns error when name is missing" do
      assert {:error, "Missing required parameter: name"} =
               ToolRegistry.execute_load_skill(%{})
    end

    test "execute_load_skill/1 handles string keys" do
      skill_path = Path.join(@fixtures_dir, "test-skill/SKILL.md")

      skill = %{
        name: "test-skill",
        description: "A test skill",
        path: skill_path
      }

      :ets.insert(:piano_skills, {skill.name, skill})

      assert {:ok, content} = ToolRegistry.execute_load_skill(%{"name" => "test-skill"})
      assert content =~ "# Test Skill"
    end
  end
end
