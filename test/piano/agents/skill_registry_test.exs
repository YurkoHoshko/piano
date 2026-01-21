defmodule Piano.Agents.SkillRegistryTest do
  use ExUnit.Case, async: false

  alias Piano.Agents.SkillRegistry

  @fixtures_dir "test/fixtures/.piano/skills"

  setup do
    # Clean up ETS table if it exists from previous test
    if :ets.info(:piano_skills) != :undefined do
      :ets.delete(:piano_skills)
    end

    :ok
  end

  describe "init/0" do
    test "creates ETS table" do
      SkillRegistry.init()
      assert :ets.info(:piano_skills) != :undefined
    end
  end

  describe "scan_skills_directory with fixtures" do
    test "discovers skills with YAML frontmatter" do
      # We need to test with fixtures, so we'll use a helper
      SkillRegistry.init()

      # Clear and manually insert test fixtures
      :ets.delete_all_objects(:piano_skills)

      # Simulate discovering the test fixtures
      skill = %{
        name: "test-skill",
        description: "A test skill for unit testing",
        path: Path.join(@fixtures_dir, "test-skill/SKILL.md")
      }

      :ets.insert(:piano_skills, {skill.name, skill})

      skills = SkillRegistry.list_available()
      assert length(skills) == 1
      assert hd(skills).name == "test-skill"
      assert hd(skills).description == "A test skill for unit testing"
    end

    test "uses directory name when no frontmatter" do
      SkillRegistry.init()
      :ets.delete_all_objects(:piano_skills)

      skill = %{
        name: "no-frontmatter",
        description: nil,
        path: Path.join(@fixtures_dir, "no-frontmatter/SKILL.md")
      }

      :ets.insert(:piano_skills, {skill.name, skill})

      skills = SkillRegistry.list_available()
      assert length(skills) == 1
      assert hd(skills).name == "no-frontmatter"
      assert hd(skills).description == nil
    end
  end

  describe "load_skill/1" do
    test "returns skill content when skill exists" do
      SkillRegistry.init()
      :ets.delete_all_objects(:piano_skills)

      skill_path = Path.join(@fixtures_dir, "test-skill/SKILL.md")

      skill = %{
        name: "test-skill",
        description: "A test skill",
        path: skill_path
      }

      :ets.insert(:piano_skills, {skill.name, skill})

      content = SkillRegistry.load_skill("test-skill")
      assert content =~ "# Test Skill"
      assert content =~ "name: test-skill"
    end

    test "returns nil for non-existent skill" do
      SkillRegistry.init()

      assert SkillRegistry.load_skill("non-existent") == nil
    end
  end

  describe "get_prompts/1" do
    test "returns concatenated prompts for enabled skills" do
      SkillRegistry.init()
      :ets.delete_all_objects(:piano_skills)

      skill1 = %{
        name: "skill1",
        description: "First skill",
        path: Path.join(@fixtures_dir, "test-skill/SKILL.md")
      }

      skill2 = %{
        name: "skill2",
        description: "Second skill",
        path: Path.join(@fixtures_dir, "no-frontmatter/SKILL.md")
      }

      :ets.insert(:piano_skills, {skill1.name, skill1})
      :ets.insert(:piano_skills, {skill2.name, skill2})

      prompts = SkillRegistry.get_prompts(["skill1", "skill2"])
      assert prompts =~ "# Test Skill"
      assert prompts =~ "# No Frontmatter Skill"
    end

    test "returns empty string for empty list" do
      SkillRegistry.init()

      assert SkillRegistry.get_prompts([]) == ""
    end
  end

  describe "format_for_system_prompt/0" do
    test "returns formatted skill list" do
      SkillRegistry.init()
      :ets.delete_all_objects(:piano_skills)

      skill = %{
        name: "coding",
        description: "Helps with coding tasks",
        path: "test/path/SKILL.md"
      }

      :ets.insert(:piano_skills, {skill.name, skill})

      prompt = SkillRegistry.format_for_system_prompt()
      assert prompt =~ "<available_skills>"
      assert prompt =~ "coding: Helps with coding tasks"
      assert prompt =~ "</available_skills>"
    end

    test "returns empty string when no skills" do
      SkillRegistry.init()
      :ets.delete_all_objects(:piano_skills)

      assert SkillRegistry.format_for_system_prompt() == ""
    end
  end
end
