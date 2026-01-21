defmodule Piano.Agents.SkillRegistry do
  @moduledoc """
  Registry for agent skills. Discovers skills from `.piano/skills/` directory.
  Each subdirectory containing a `SKILL.md` file becomes a skill.
  YAML frontmatter is parsed to extract name and description.
  """

  @skills_dir ".piano/skills"
  @ets_table :piano_skills

  @type skill :: %{
          name: String.t(),
          description: String.t() | nil,
          path: String.t()
        }

  @doc """
  Initializes the skill registry ETS table and discovers available skills.
  Called during application startup.
  """
  @spec init() :: :ok
  def init do
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])
    discover_skills()
    :ok
  end

  @doc """
  Discovers all skills from `.piano/skills/` and stores them in ETS.
  """
  @spec discover_skills() :: :ok
  def discover_skills do
    skills = scan_skills_directory()

    Enum.each(skills, fn skill ->
      :ets.insert(@ets_table, {skill.name, skill})
    end)

    :ok
  end

  @doc """
  Returns a list of all available skill metadata (name, description, path).
  """
  @spec list_available() :: [skill()]
  def list_available do
    case :ets.info(@ets_table) do
      :undefined -> []
      _ -> :ets.tab2list(@ets_table) |> Enum.map(fn {_name, skill} -> skill end)
    end
  end

  @doc """
  Returns concatenated prompt text for the given list of enabled skill names.
  Loads full SKILL.md content for each enabled skill.
  """
  @spec get_prompts([String.t()]) :: String.t()
  def get_prompts(enabled_skill_names) when is_list(enabled_skill_names) do
    enabled_skill_names
    |> Enum.map(&load_skill/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  @doc """
  Loads a single skill's full SKILL.md content by name.
  Returns nil if the skill doesn't exist.
  """
  @spec load_skill(String.t()) :: String.t() | nil
  def load_skill(skill_name) do
    case :ets.info(@ets_table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@ets_table, skill_name) do
          [{^skill_name, skill}] ->
            case File.read(skill.path) do
              {:ok, content} -> content
              {:error, _} -> nil
            end

          [] ->
            nil
        end
    end
  end

  @doc """
  Returns a formatted string describing available skills for the LLM system prompt.
  """
  @spec format_for_system_prompt() :: String.t()
  def format_for_system_prompt do
    skills = list_available()

    if Enum.empty?(skills) do
      ""
    else
      skill_list =
        skills
        |> Enum.sort_by(& &1.name)
        |> Enum.map(fn skill ->
          desc = skill.description || "No description"
          "- #{skill.name}: #{desc}"
        end)
        |> Enum.join("\n")

      """
      <available_skills>
      The following skills are available. Use the load_skill tool to load a skill's full instructions.

      #{skill_list}
      </available_skills>
      """
    end
  end

  # Private functions

  defp scan_skills_directory do
    case File.ls(@skills_dir) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(@skills_dir, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.map(&parse_skill_dir/1)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  defp parse_skill_dir(dir_path) do
    skill_md_path = Path.join(dir_path, "SKILL.md")

    case File.read(skill_md_path) do
      {:ok, content} ->
        {name, description} = parse_frontmatter(content, dir_path)

        %{
          name: name,
          description: description,
          path: skill_md_path
        }

      {:error, _} ->
        nil
    end
  end

  defp parse_frontmatter(content, dir_path) do
    default_name = Path.basename(dir_path)

    case extract_yaml_block(content) do
      nil ->
        {default_name, nil}

      yaml_content ->
        case YamlElixir.read_from_string(yaml_content) do
          {:ok, data} when is_map(data) ->
            name = Map.get(data, "name") || default_name
            description = Map.get(data, "description")
            {name, description}

          _ ->
            {default_name, nil}
        end
    end
  end

  defp extract_yaml_block(content) do
    # YAML frontmatter is between --- delimiters at the start of the file
    case String.split(content, ~r/^---\s*$/m, parts: 3) do
      ["", yaml, _rest] -> String.trim(yaml)
      _ -> nil
    end
  end
end
