defmodule Piano.Agents.ToolRegistry do
  @moduledoc """
  Registry for agent tools. Defines available tools with their schemas and callbacks.
  """

  @type tool :: %{
          name: String.t(),
          description: String.t(),
          parameters: map(),
          callback: (map() -> {:ok, String.t()} | {:error, String.t()})
        }

  @tools %{
    "read_file" => %{
      name: "read_file",
      description: "Read the contents of a file at the given path",
      parameters: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "The file path to read"}
        },
        required: ["path"]
      },
      callback: &__MODULE__.execute_read_file/1
    },
    "create_file" => %{
      name: "create_file",
      description: "Create a new file with the given content",
      parameters: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "The file path to create"},
          content: %{type: "string", description: "The content to write to the file"}
        },
        required: ["path", "content"]
      },
      callback: &__MODULE__.execute_create_file/1
    },
    "edit_file" => %{
      name: "edit_file",
      description: "Edit an existing file by replacing old content with new content",
      parameters: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "The file path to edit"},
          old_content: %{type: "string", description: "The content to find and replace"},
          new_content: %{type: "string", description: "The replacement content"}
        },
        required: ["path", "old_content", "new_content"]
      },
      callback: &__MODULE__.execute_edit_file/1
    },
    "bash" => %{
      name: "bash",
      description: "Execute a shell command and return the output",
      parameters: %{
        type: "object",
        properties: %{
          command: %{type: "string", description: "The shell command to execute"}
        },
        required: ["command"]
      },
      callback: &__MODULE__.execute_bash/1
    }
  }

  @doc """
  Returns a list of all available tool names.
  """
  @spec list_available() :: [String.t()]
  def list_available do
    Map.keys(@tools)
  end

  @doc """
  Returns tool definitions for the given list of enabled tool names.
  """
  @spec get_tools([String.t()]) :: [tool()]
  def get_tools(enabled_tool_names) when is_list(enabled_tool_names) do
    enabled_tool_names
    |> Enum.filter(&Map.has_key?(@tools, &1))
    |> Enum.map(&Map.get(@tools, &1))
  end

  @doc """
  Execute the read_file tool.
  """
  @spec execute_read_file(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_read_file(%{"path" => path}) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  def execute_read_file(_), do: {:error, "Missing required parameter: path"}

  @doc """
  Execute the create_file tool.
  """
  @spec execute_create_file(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_create_file(%{"path" => path, "content" => content}) do
    with :ok <- path |> Path.dirname() |> File.mkdir_p(),
         :ok <- File.write(path, content) do
      {:ok, "File created successfully: #{path}"}
    else
      {:error, reason} -> {:error, "Failed to create file: #{inspect(reason)}"}
    end
  end

  def execute_create_file(_), do: {:error, "Missing required parameters: path, content"}

  @doc """
  Execute the edit_file tool.
  """
  @spec execute_edit_file(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_edit_file(%{"path" => path, "old_content" => old_content, "new_content" => new_content}) do
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

  def execute_edit_file(_), do: {:error, "Missing required parameters: path, old_content, new_content"}

  @doc """
  Execute the bash tool.
  """
  @spec execute_bash(map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_bash(%{"command" => command}) do
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

  def execute_bash(_), do: {:error, "Missing required parameter: command"}
end
