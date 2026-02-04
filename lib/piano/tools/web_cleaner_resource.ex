defmodule Piano.Tools.WebCleanerResource do
  @moduledoc """
  Ash resource wrapper for WebCleaner (webfetch) tool calls via MCP.

  This resource wraps the WebCleaner module to expose web fetching
  and content extraction as Ash actions that can be called via MCP.

  ## Output Format

  All actions return large content as file references to prevent context overflow:
  - `preview`: First ~100 characters of content
  - `path`: Full path to the saved file containing complete content
  - `size`: Total character count
  - `truncated`: Boolean indicating if preview was truncated

  Use the `path` to read the full content when needed via file tools.
  """

  use Ash.Resource, domain: nil

  alias Piano.Tools.WebCleaner
  alias Piano.Tools.FileOutput

  actions do
    # Fetch and clean webpage
    action :fetch, :map do
      description "Fetch a webpage and extract clean, LLM-friendly text content. Output saved to file - returns preview and file path."

      argument :url, :string do
        allow_nil? false
        description "The URL to fetch content from"
      end

      argument :format, :atom do
        description "Output format: :text, :markdown, :html"
        default :text
      end

      run fn input, _ctx ->
        url = input.arguments.url
        format = input.arguments.format
        format_ext = format_to_extension(format)

        case WebCleaner.fetch_and_clean(url, format: format) do
          {:ok, content} ->
            # Save to file and return preview + path
            case FileOutput.save(content,
                   format: format_ext,
                   prefix: "webfetch",
                   subdirectory: "web"
                 ) do
              {:ok, file_info} ->
                {:ok,
                 %{
                   preview: file_info.preview,
                   path: file_info.path,
                   size: file_info.size,
                   truncated: file_info.truncated,
                   format: format,
                   url: url
                 }}

              {:error, reason} ->
                {:error, "Failed to save output: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Failed to fetch URL: #{reason}"}
        end
      end
    end

    # Quick text extraction
    action :extract_text, :map do
      description "Quickly extract text content from a URL. Output saved to file - returns preview and file path."

      argument :url, :string do
        allow_nil? false
        description "The URL to extract text from"
      end

      run fn input, _ctx ->
        url = input.arguments.url

        case WebCleaner.fetch_and_clean(url, format: :text) do
          {:ok, content} ->
            # Save to file and return preview + path
            case FileOutput.save(content,
                   format: "txt",
                   prefix: "webfetch_text",
                   subdirectory: "web"
                 ) do
              {:ok, file_info} ->
                {:ok,
                 %{
                   preview: file_info.preview,
                   path: file_info.path,
                   size: file_info.size,
                   truncated: file_info.truncated,
                   format: :text,
                   url: url
                 }}

              {:error, reason} ->
                {:error, "Failed to save output: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Failed to extract text: #{reason}"}
        end
      end
    end

    # Extract markdown
    action :extract_markdown, :map do
      description "Extract content as markdown from a URL. Output saved to file - returns preview and file path."

      argument :url, :string do
        allow_nil? false
        description "The URL to extract markdown from"
      end

      run fn input, _ctx ->
        url = input.arguments.url

        case WebCleaner.fetch_and_clean(url, format: :markdown) do
          {:ok, content} ->
            # Save to file and return preview + path
            case FileOutput.save(content,
                   format: "md",
                   prefix: "webfetch_md",
                   subdirectory: "web"
                 ) do
              {:ok, file_info} ->
                {:ok,
                 %{
                   preview: file_info.preview,
                   path: file_info.path,
                   size: file_info.size,
                   truncated: file_info.truncated,
                   format: :markdown,
                   url: url
                 }}

              {:error, reason} ->
                {:error, "Failed to save output: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Failed to extract markdown: #{reason}"}
        end
      end
    end

    # Structured extraction (title, headings, links, etc.)
    action :extract_structured, :map do
      description "Extract structured content (title, headings, links, paragraphs). Output saved as JSON file - returns preview and file path."

      argument :url, :string do
        allow_nil? false
        description "The URL to extract structured content from"
      end

      run fn input, _ctx ->
        url = input.arguments.url

        # First fetch the HTML
        case WebCleaner.fetch(url) do
          {:ok, html} ->
            # Then parse it for structured data
            case WebCleaner.clean(html, :structured) do
              {:ok, structured} ->
                # Save structured data as JSON
                data = Map.merge(structured, %{url: url, format: :structured})

                case FileOutput.save_json(data,
                       prefix: "webfetch_structured",
                       subdirectory: "web"
                     ) do
                  {:ok, file_info} ->
                    {:ok,
                     %{
                       preview: file_info.preview,
                       path: file_info.path,
                       size: file_info.size,
                       truncated: file_info.truncated,
                       format: :structured,
                       url: url
                     }}

                  {:error, reason} ->
                    {:error, "Failed to save output: #{reason}"}
                end

              {:error, reason} ->
                {:error, "Failed to parse content: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Failed to fetch URL: #{reason}"}
        end
      end
    end
  end

  # Helper function to convert format atom to file extension
  defp format_to_extension(:text), do: "txt"
  defp format_to_extension(:markdown), do: "md"
  defp format_to_extension(:html), do: "html"
  defp format_to_extension(_), do: "txt"
end
