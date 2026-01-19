defmodule Piano.Agents.SkillRegistry do
  @moduledoc """
  Registry for agent skills. Loads skill prompts from `.agents/skills/` directory.
  Each `.md` file becomes a skill keyed by its filename (without extension).
  """

  @skills_dir ".agents/skills"

  @doc """
  Returns a list of all available skill names.
  Scans the skills directory for `.md` files.
  """
  @spec list_available() :: [String.t()]
  def list_available do
    case File.ls(@skills_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(&String.trim_trailing(&1, ".md"))

      {:error, _} ->
        []
    end
  end

  @doc """
  Returns concatenated prompt text for the given list of enabled skill names.
  """
  @spec get_prompts([String.t()]) :: String.t()
  def get_prompts(enabled_skill_names) when is_list(enabled_skill_names) do
    enabled_skill_names
    |> Enum.map(&load_skill/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  @doc """
  Loads a single skill's content by name.
  Returns nil if the skill file doesn't exist.
  """
  @spec load_skill(String.t()) :: String.t() | nil
  def load_skill(skill_name) do
    path = Path.join(@skills_dir, "#{skill_name}.md")

    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> nil
    end
  end
end
