defmodule Piano.Tools.FileOutput do
  @moduledoc """
  Utility module for saving tool outputs to the filesystem.

  Provides standardized file storage for large tool outputs to prevent
  context window overflow. Returns a preview of the content and the file path.
  """

  require Logger

  @default_preview_length 100
  @output_dir "/piano/agents/mcp-outputs"

  @doc """
  Saves content to a file and returns a preview with the file path.

  ## Options
    * `:format` - File format/extension (default: "txt")
    * `:prefix` - Filename prefix (default: "output")
    * `:preview_length` - Length of preview text (default: #{@default_preview_length})
    * `:subdirectory` - Subdirectory within output dir (default: nil)

  ## Returns
    * `{:ok, %{preview: string, path: string, size: integer}}`
    * `{:error, reason}`

  ## Examples
      iex> FileOutput.save("Large content here...", format: "txt", prefix: "webfetch")
      {:ok, %{preview: "Large cont...", path: "/piano/agents/mcp-outputs/fetch_1234567890.txt", size: 1234}}
  """
  def save(content, opts \\ []) do
    format = Keyword.get(opts, :format, "txt")
    prefix = Keyword.get(opts, :prefix, "output")
    preview_length = Keyword.get(opts, :preview_length, @default_preview_length)
    subdirectory = Keyword.get(opts, :subdirectory)

    # Build the output directory path
    output_dir =
      if subdirectory do
        Path.join(@output_dir, subdirectory)
      else
        @output_dir
      end

    # Ensure directory exists
    case File.mkdir_p(output_dir) do
      :ok ->
        # Generate timestamped filename
        timestamp = System.os_time(:millisecond)
        filename = "#{prefix}_#{timestamp}.#{format}"
        filepath = Path.join(output_dir, filename)

        # Write content to file
        case File.write(filepath, content) do
          :ok ->
            size = String.length(content)
            preview = generate_preview(content, preview_length)

            Logger.info("Tool output saved to file",
              path: filepath,
              size: size,
              preview_length: preview_length
            )

            {:ok,
             %{
               preview: preview,
               path: filepath,
               size: size,
               truncated: size > preview_length
             }}

          {:error, reason} ->
            Logger.error("Failed to write output file", path: filepath, reason: inspect(reason))
            {:error, "Failed to save output: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Logger.error("Failed to create output directory",
          path: output_dir,
          reason: inspect(reason)
        )

        {:error, "Failed to create output directory: #{inspect(reason)}"}
    end
  end

  @doc """
  Saves structured data as JSON to a file.

  ## Options
    * `:prefix` - Filename prefix (default: "data")
    * `:preview_length` - Length of preview text (default: #{@default_preview_length})
    * `:subdirectory` - Subdirectory within output dir (default: nil)

  ## Returns
    * `{:ok, %{preview: string, path: string, size: integer}}`
    * `{:error, reason}`
  """
  def save_json(data, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "data")
    subdirectory = Keyword.get(opts, :subdirectory)

    # Convert to JSON string
    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        save(json,
          format: "json",
          prefix: prefix,
          subdirectory: subdirectory,
          preview_length: Keyword.get(opts, :preview_length, @default_preview_length)
        )

      {:error, reason} ->
        {:error, "Failed to encode data to JSON: #{inspect(reason)}"}
    end
  end

  @doc """
  Generates a preview of the content, truncated with ellipsis if necessary.

  ## Examples
      iex> FileOutput.generate_preview("Hello World", 5)
      "Hello..."

      iex> FileOutput.generate_preview("Hi", 10)
      "Hi"
  """
  def generate_preview(content, length \\ @default_preview_length) do
    content
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> then(fn text ->
      if String.length(text) > length do
        String.slice(text, 0, length) <> "..."
      else
        text
      end
    end)
  end

  @doc """
  Returns the configured output directory.
  """
  def output_dir, do: @output_dir
end
