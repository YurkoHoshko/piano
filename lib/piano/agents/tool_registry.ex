defmodule Piano.Agents.ToolRegistry do
  @moduledoc """
  Registry for agent tools. Defines available tools with their schemas and callbacks.
  """

  @type tool :: ReqLLM.Tool.t()

  @tools [
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
      description: "Execute a shell command and return the output",
      parameter_schema: [
        command: [type: :string, required: true, doc: "The shell command to execute"]
      ],
      callback: &__MODULE__.execute_bash/1
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

          result = """
          Exit code: #{exit_code}
          Output:
          #{output}
          """

          {:ok, result}
        rescue
          e -> {:error, "Command execution failed: #{Exception.message(e)}"}
        end
    end
  end

  def execute_bash(_), do: {:error, "Missing required parameter: command"}

  defp fetch_param(args, key) when is_atom(key) do
    Map.get(args, key) || Map.get(args, Atom.to_string(key))
  end

  defp fetch_param(args, key) when is_binary(key) do
    Map.get(args, key) || Map.get(args, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(args, key)
  end
end
