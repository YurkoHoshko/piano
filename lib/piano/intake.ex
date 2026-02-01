defmodule Piano.Intake do
  @moduledoc """
  Manages file/media intake for agent processing.

  Creates intake folder structure: .agents/intake/<surface>/<interaction-id>/
  and provides utilities for saving and referencing files sent to the agent.
  """

  require Logger

  @intake_base_dir ".agents/intake"

  @doc """
  Gets the base intake directory path.
  """
  @spec base_dir() :: String.t()
  def base_dir, do: @intake_base_dir

  @doc """
  Creates an intake folder for a specific interaction.
  Returns the full path to the interaction's intake folder.
  """
  @spec create_interaction_folder(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def create_interaction_folder(surface, interaction_id) do
    path = Path.join([@intake_base_dir, sanitize(surface), sanitize(interaction_id)])

    case File.mkdir_p(path) do
      :ok ->
        Logger.info("Created intake folder",
          path: path,
          surface: surface,
          interaction_id: interaction_id
        )

        {:ok, path}

      {:error, reason} ->
        Logger.error("Failed to create intake folder", path: path, reason: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Saves a file to the intake folder for an interaction.
  Returns the full path to the saved file.
  """
  @spec save_file(String.t(), String.t(), binary()) :: {:ok, String.t()} | {:error, term()}
  def save_file(intake_path, filename, content) when is_binary(content) do
    safe_filename = sanitize(filename)
    file_path = Path.join(intake_path, safe_filename)

    case File.write(file_path, content) do
      :ok ->
        Logger.info("Saved file to intake", path: file_path, size: byte_size(content))
        {:ok, file_path}

      {:error, reason} ->
        Logger.error("Failed to save file to intake", path: file_path, reason: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Lists all files in an intake folder.
  """
  @spec list_files(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_files(intake_path) do
    case File.ls(intake_path) do
      {:ok, files} ->
        files
        |> Enum.map(fn f -> Path.join(intake_path, f) end)
        |> Enum.filter(&File.regular?/1)
        |> then(&{:ok, &1})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a context message about available files for the agent.
  """
  @spec generate_context(String.t()) :: String.t()
  def generate_context(intake_path) do
    case list_files(intake_path) do
      {:ok, []} ->
        ""

      {:ok, files} ->
        file_list =
          Enum.map_join(files, "\n", fn path ->
            filename = Path.basename(path)
            size = file_size_string(path)
            "  - #{filename} (#{size})"
          end)

        """
        📎 **Files available for processing:**
        #{file_list}

        You can reference these files by path: `#{intake_path}/<filename>`
        """

      {:error, _} ->
        ""
    end
  end

  @doc """
  Cleans up an intake folder after processing is complete.
  """
  @spec cleanup(String.t()) :: :ok | {:error, term()}
  def cleanup(intake_path) do
    case File.rm_rf(intake_path) do
      {:ok, _} ->
        Logger.info("Cleaned up intake folder", path: intake_path)
        :ok

      {:error, reason, _} ->
        Logger.error("Failed to cleanup intake folder",
          path: intake_path,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp sanitize(string) when is_binary(string) do
    string
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")
    |> String.trim()
  end

  defp file_size_string(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size < 1024 -> "#{size} B"
      {:ok, %{size: size}} when size < 1024 * 1024 -> "#{div(size, 1024)} KB"
      {:ok, %{size: size}} -> "#{div(size, 1024 * 1024)} MB"
      _ -> "unknown size"
    end
  end
end
