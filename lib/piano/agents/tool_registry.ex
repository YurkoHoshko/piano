defmodule Piano.Agents.ToolRegistry do
  @moduledoc """
  Registry for agent tools. Defines available tools with their schemas and callbacks.
  """

  alias Piano.Agents.SkillRegistry

  @type tool :: ReqLLM.Tool.t()

  @tools [
    [
      name: "load_skill",
      description:
        "Load a skill's full instructions by name. Use this to load specialized workflows and capabilities from available skills.",
      parameter_schema: [
        name: [type: :string, required: true, doc: "The name of the skill to load"]
      ],
      callback: &__MODULE__.execute_load_skill/1
    ],
    [
      name: "read_file",
      description: "Read the contents of a file at the given path",
      parameter_schema: [
        path: [type: :string, required: true, doc: "The file path to read"]
      ],
      callback: &__MODULE__.execute_read_file/1
    ],
    [
      name: "create_file",
      description: "Create a new file with the given content",
      parameter_schema: [
        path: [type: :string, required: true, doc: "The file path to create"],
        content: [type: :string, required: true, doc: "The content to write to the file"]
      ],
      callback: &__MODULE__.execute_create_file/1
    ],
    [
      name: "edit_file",
      description: "Edit an existing file by replacing old content with new content",
      parameter_schema: [
        path: [type: :string, required: true, doc: "The file path to edit"],
        old_content: [type: :string, required: true, doc: "The content to find and replace"],
        new_content: [type: :string, required: true, doc: "The replacement content"]
      ],
      callback: &__MODULE__.execute_edit_file/1
    ],
    [
      name: "bash",
      description:
        "Execute a shell command and return the output. If return_direct is true, the tool may return output intended for direct reply and skip further LLM processing.",
      parameter_schema: [
        command: [type: :string, required: true, doc: "The shell command to execute"],
        return_direct: [
          type: :boolean,
          required: false,
          doc: "If true, return output suitable for direct reply without another LLM call"
        ]
      ],
      callback: &__MODULE__.execute_bash/1
    ],
    [
      name: "edit_soul",
      description:
        "Edit your own soul (personality, directives, preferences). Use this to remember important context, update your behavior, or refine how you respond. Your soul persists across conversations.",
      parameter_schema: [
        action: [
          type: :string,
          required: true,
          doc: "One of: 'read' (view current soul), 'append' (add to soul), 'replace' (overwrite soul)"
        ],
        content: [
          type: :string,
          required: false,
          doc: "The content to append or replace (required for append/replace actions)"
        ]
      ],
      callback: :execute_edit_soul,
      requires_context: true
    ]
  ]

  @doc """
  Returns a list of all available tool names.
  """
  @spec list_available() :: [String.t()]
  def list_available do
    Enum.map(@tools, &Keyword.fetch!(&1, :name))
  end

  @doc """
  Returns tool definitions for the given list of enabled tool names.
  """
  @spec get_tools([String.t()]) :: [tool()]
  def get_tools(enabled_tool_names) when is_list(enabled_tool_names) do
    @tools
    |> Enum.filter(&(Keyword.fetch!(&1, :name) in enabled_tool_names))
    |> Enum.map(fn tool ->
      if Keyword.get(tool, :requires_context, false) do
        callback = Keyword.fetch!(tool, :callback)

        tool
        |> Keyword.put(:callback, {__MODULE__, callback, [%{}]})
        |> Keyword.drop([:requires_context])
      else
        Keyword.drop(tool, [:requires_context])
      end
    end)
    |> Enum.map(&ReqLLM.Tool.new!/1)
  end

  @doc """
  Execute the read_file tool.
  """
  @spec execute_read_file(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_read_file(args) when is_map(args) do
    case fetch_param(args, :path) do
      nil ->
        {:error, "Missing required parameter: path"}

      path ->
        case File.read(path) do
          {:ok, content} -> {:ok, content}
          {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
        end
    end
  end

  def execute_read_file(_), do: {:error, "Missing required parameter: path"}

  @doc """
  Execute the load_skill tool.
  """
  @spec execute_load_skill(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_load_skill(args) when is_map(args) do
    case fetch_param(args, :name) do
      nil ->
        {:error, "Missing required parameter: name"}

      skill_name ->
        case SkillRegistry.load_skill(skill_name) do
          nil -> {:error, "Skill not found: #{skill_name}"}
          content -> {:ok, content}
        end
    end
  end

  def execute_load_skill(_), do: {:error, "Missing required parameter: name"}

  @doc """
  Execute the create_file tool.
  """
  @spec execute_create_file(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_create_file(args) when is_map(args) do
    path = fetch_param(args, :path)
    content = fetch_param(args, :content)

    if is_nil(path) or is_nil(content) do
      {:error, "Missing required parameters: path, content"}
    else
      with :ok <- path |> Path.dirname() |> File.mkdir_p(),
           :ok <- File.write(path, content) do
        {:ok, "File created successfully: #{path}"}
      else
        {:error, reason} -> {:error, "Failed to create file: #{inspect(reason)}"}
      end
    end
  end

  def execute_create_file(_), do: {:error, "Missing required parameters: path, content"}

  @doc """
  Execute the edit_file tool.
  """
  @spec execute_edit_file(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_edit_file(args) when is_map(args) do
    path = fetch_param(args, :path)
    old_content = fetch_param(args, :old_content)
    new_content = fetch_param(args, :new_content)

    if is_nil(path) or is_nil(old_content) or is_nil(new_content) do
      {:error, "Missing required parameters: path, old_content, new_content"}
    else
      case File.read(path) do
        {:ok, content} ->
          if String.contains?(content, old_content) do
            new_file_content = String.replace(content, old_content, new_content, global: false)

            case File.write(path, new_file_content) do
              :ok -> {:ok, "File edited successfully: #{path}"}
              {:error, reason} -> {:error, "Failed to write file: #{inspect(reason)}"}
            end
          else
            {:error, "old_content not found in file"}
          end

        {:error, reason} ->
          {:error, "Failed to read file: #{inspect(reason)}"}
      end
    end
  end

  def execute_edit_file(_),
    do: {:error, "Missing required parameters: path, old_content, new_content"}

  @doc """
  Execute the bash tool.
  """
  @spec execute_bash(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_bash(args) when is_map(args) do
    case fetch_param(args, :command) do
      nil ->
        {:error, "Missing required parameter: command"}

      command ->
        try do
          {output, exit_code} = System.cmd("sh", ["-c", command], stderr_to_stdout: true)
          return_direct = fetch_param(args, :return_direct) == true
          {output, truncated?} = truncate_output(output)

          if return_direct do
            {:ok, %{output: output, return_direct: true, exit_code: exit_code, truncated: truncated?}}
          else
            result = """
            Exit code: #{exit_code}
            Output:
            #{output}
            """

            {:ok, append_truncation_notice(result, truncated?)}
          end
        rescue
          e -> {:error, "Command execution failed: #{Exception.message(e)}"}
        end
    end
  end

  def execute_bash(_), do: {:error, "Missing required parameter: command"}

  @doc """
  Execute the edit_soul tool. Requires agent context.
  """
  @spec execute_edit_soul(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_edit_soul(args, context) when is_map(args) and is_map(context) do
    action = fetch_param(args, :action)
    content = fetch_param(args, :content)
    agent = Map.get(context, :agent)

    cond do
      is_nil(agent) ->
        {:error, "Agent context not available"}

      is_nil(action) ->
        {:error, "Missing required parameter: action"}

      action not in ["read", "append", "replace"] ->
        {:error, "Invalid action. Must be one of: read, append, replace"}

      action == "read" ->
        soul = agent.soul || "(empty)"
        {:ok, "Current soul:\n#{soul}"}

      action in ["append", "replace"] and (is_nil(content) or content == "") ->
        {:error, "Missing required parameter: content (required for #{action} action)"}

      action == "append" ->
        case Ash.update(agent, %{soul: content}, action: :append_soul) do
          {:ok, updated} -> {:ok, "Soul updated. New soul:\n#{updated.soul}"}
          {:error, error} -> {:error, "Failed to update soul: #{inspect(error)}"}
        end

      action == "replace" ->
        case Ash.update(agent, %{soul: content}, action: :rewrite_soul) do
          {:ok, updated} -> {:ok, "Soul replaced. New soul:\n#{updated.soul}"}
          {:error, error} -> {:error, "Failed to replace soul: #{inspect(error)}"}
        end
    end
  end

  def execute_edit_soul(_, _), do: {:error, "Missing required parameter: action"}

  @doc """
  Check if a tool requires context (like agent info).
  """
  @spec requires_context?(String.t()) :: boolean()
  def requires_context?(tool_name) do
    @tools
    |> Enum.find(&(Keyword.fetch!(&1, :name) == tool_name))
    |> case do
      nil -> false
      tool -> Keyword.get(tool, :requires_context, false)
    end
  end

  @doc """
  Execute a tool by name with args and optional context.
  """
  @spec execute(String.t(), map(), map()) :: {:ok, any()} | {:error, String.t()}
  def execute(tool_name, args, context \\ %{}) do
    case Enum.find(@tools, &(Keyword.fetch!(&1, :name) == tool_name)) do
      nil ->
        {:error, "Unknown tool: #{tool_name}"}

      tool ->
        callback = Keyword.fetch!(tool, :callback)
        requires_context = Keyword.get(tool, :requires_context, false)

        if requires_context do
          apply(__MODULE__, callback, [args, context])
        else
          callback.(args)
        end
    end
  end

  defp fetch_param(args, key) when is_atom(key) do
    Map.get(args, key) || Map.get(args, Atom.to_string(key))
  end

  defp fetch_param(args, key) when is_binary(key) do
    Map.get(args, key) || Map.get(args, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(args, key)
  end

  defp truncate_output(output) when is_binary(output) do
    max_chars = 8192

    if String.length(output) > max_chars do
      {String.slice(output, 0, max_chars), true}
    else
      {output, false}
    end
  end

  defp append_truncation_notice(result, true) do
    result <> "\n[Output truncated to 2048 tokens]\n"
  end

  defp append_truncation_notice(result, false), do: result
end
