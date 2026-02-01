defmodule Piano.Tools.WebCleanerResource do
  @moduledoc """
  Ash resource wrapper for WebCleaner (webfetch) tool calls via MCP.

  This resource wraps the WebCleaner module to expose web fetching
  and content extraction as Ash actions that can be called via MCP.
  """

  use Ash.Resource

  alias Piano.Tools.WebCleaner

  actions do
    # Fetch and clean webpage
    action :fetch, :map do
      description "Fetch a webpage and extract clean, LLM-friendly text content"

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

        case WebCleaner.fetch_and_clean(url, format: format) do
          {:ok, content} ->
            {:ok,
             %{
               content: content,
               format: format,
               url: url,
               length: String.length(content)
             }}

          {:error, reason} ->
            {:error, "Failed to fetch URL: #{reason}"}
        end
      end
    end

    # Quick text extraction
    action :extract_text, :map do
      description "Quickly extract text content from a URL (text format only)"

      argument :url, :string do
        allow_nil? false
        description "The URL to extract text from"
      end

      run fn input, _ctx ->
        url = input.arguments.url

        case WebCleaner.fetch_and_clean(url, format: :text) do
          {:ok, content} ->
            # Truncate if too long for LLM context
            truncated =
              if String.length(content) > 10000 do
                String.slice(content, 0, 10000) <> "\n\n[Content truncated...]"
              else
                content
              end

            {:ok,
             %{
               content: truncated,
               format: :text,
               url: url,
               original_length: String.length(content),
               truncated: String.length(content) > 10000
             }}

          {:error, reason} ->
            {:error, "Failed to extract text: #{reason}"}
        end
      end
    end

    # Extract markdown
    action :extract_markdown, :map do
      description "Extract content as markdown from a URL"

      argument :url, :string do
        allow_nil? false
        description "The URL to extract markdown from"
      end

      run fn input, _ctx ->
        url = input.arguments.url

        case WebCleaner.fetch_and_clean(url, format: :markdown) do
          {:ok, content} ->
            {:ok,
             %{
               content: content,
               format: :markdown,
               url: url,
               length: String.length(content)
             }}

          {:error, reason} ->
            {:error, "Failed to extract markdown: #{reason}"}
        end
      end
    end

    # Structured extraction (title, headings, links, etc.)
    action :extract_structured, :map do
      description "Extract structured content (title, headings, links, paragraphs)"

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
                {:ok, Map.merge(structured, %{url: url, format: :structured})}

              {:error, reason} ->
                {:error, "Failed to parse content: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Failed to fetch URL: #{reason}"}
        end
      end
    end
  end
end
