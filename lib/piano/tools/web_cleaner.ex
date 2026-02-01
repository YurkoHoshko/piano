defmodule Piano.Tools.WebCleaner do
  @moduledoc """
  Web content cleaning tool using Req and Floki.

  Fetches web pages and extracts clean, LLM-friendly text by:
  - Removing noise elements (script, style, nav, footer, etc.)
  - Preferring semantic containers (main, article)
  - Using scoring heuristic: (text_len - link_text_len) as fallback
  """

  require Logger

  @noise_tags [
    "script",
    "style",
    "noscript",
    "iframe",
    "object",
    "embed",
    "nav",
    "footer",
    "header",
    "aside",
    "menu",
    "dialog",
    "svg",
    "canvas",
    "video",
    "audio",
    "source",
    "track",
    "template",
    "portal",
    "slot",
    "form",
    "input",
    "button",
    "select",
    "textarea",
    "label",
    "fieldset",
    "legend",
    "details",
    "summary",
    "address"
  ]

  @preferred_tags ["main", "article"]

  @doc """
  Fetch and clean a webpage.

  ## Options
    * `:format` - Output format: `:text`, `:markdown`, `:html` (default: `:text`)
    * `:timeout` - Request timeout in milliseconds (default: 30000)

  ## Examples
      iex> Piano.Tools.WebCleaner.fetch_and_clean("https://example.com")
      {:ok, "Example Domain\\nThis domain is for use in documentation..."}
      
      iex> Piano.Tools.WebCleaner.fetch_and_clean("https://example.com", format: :markdown)
      {:ok, "# Example Domain\\n\\nThis domain is for use in documentation..."}
  """
  def fetch_and_clean(url, opts \\ []) do
    # Ensure Req/Finch are started (idempotent)
    Application.ensure_all_started(:req)

    format = Keyword.get(opts, :format, :text)
    timeout = Keyword.get(opts, :timeout, 30_000)

    with {:ok, html} <- fetch(url, timeout) do
      clean(html, format)
    end
  end

  @doc """
  Fetch raw HTML from a URL.
  """
  def fetch(url, timeout \\ 30_000) do
    headers = [
      {"user-agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"},
      {"accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"accept-language", "en-US,en;q=0.9"}
    ]

    case Req.get(url, headers: headers, max_redirects: 5, connect_options: [timeout: timeout]) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 403}} ->
        # Retry with honest UA if potentially blocked
        case Req.get(url, headers: [{"user-agent", "PianoWebCleaner/1.0"}], max_redirects: 5) do
          {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
          {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
          {:error, reason} -> {:error, "Request failed: #{inspect(reason)}"}
        end

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Clean HTML content and extract text.

  ## Options
    * `:format` - `:text`, `:markdown`, or `:html`
  """
  def clean(html, format \\ :text) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> remove_noise_elements()
        |> extract_main_content()
        |> format_content(format)

      {:error, reason} ->
        {:error, "Failed to parse HTML: #{inspect(reason)}"}
    end
  end

  # Remove script, style, nav, footer, etc.
  defp remove_noise_elements(document) do
    @noise_tags
    |> Enum.reduce(document, fn tag, doc ->
      Floki.find_and_update(doc, tag, fn _ -> :delete end)
    end)
  end

  # Try to find the best content container
  defp extract_main_content(document) do
    # First, look for semantic tags
    preferred = Enum.flat_map(@preferred_tags, &Floki.find(document, &1))

    if preferred != [] do
      # Use the largest preferred container
      preferred
      |> Enum.max_by(fn el ->
        el
        |> Floki.text()
        |> String.length()
      end)
    else
      # Score all containers and pick the best one
      document
      |> score_containers()
      |> Enum.max_by(fn {_el, score} -> score end)
      |> elem(0)
    end
  end

  # Score containers by (text_len - link_text_len)
  defp score_containers(document) do
    document
    |> Floki.find("div, section, article, main")
    |> Enum.map(fn el ->
      text = Floki.text(el)

      link_text =
        el
        |> Floki.find("a")
        |> Enum.map_join(" ", &Floki.text/1)

      text_len = String.length(text)
      link_len = String.length(link_text)

      # Score: prefer longer text, penalize link-heavy content
      score =
        if text_len < 100 do
          -1000
        else
          text_len - link_len + div(text_len, 10)
        end

      {el, score}
    end)
    |> Enum.reject(fn {_el, score} -> score < 0 end)
    |> case do
      [] ->
        # Fallback to body if no good containers found
        case Floki.find(document, "body") do
          [body] -> [{body, 0}]
          _ -> [{document, 0}]
        end

      scored ->
        scored
    end
  end

  # Format content based on requested format
  defp format_content(element, :text) do
    element
    |> Floki.text(sep: "\n")
    |> normalize_whitespace()
    |> then(&{:ok, &1})
  end

  defp format_content(element, :markdown) do
    markdown =
      element
      |> Floki.children()
      |> Enum.map_join("\n\n", &to_markdown/1)
      |> normalize_whitespace()

    {:ok, markdown}
  end

  defp format_content(element, :html) do
    html = Floki.raw_html(element)
    {:ok, html}
  end

  # Convert HTML elements to markdown
  defp to_markdown({tag, _attrs, children}) when tag in ["h1", "h2"] do
    text = Floki.text(children)
    level = if tag == "h1", do: "# ", else: "## "
    level <> text
  end

  defp to_markdown({tag, _attrs, children}) when tag in ["h3", "h4", "h5", "h6"] do
    text = Floki.text(children)
    level = String.duplicate("#", String.to_integer(String.replace_leading(tag, "h", "")))
    level <> " " <> text
  end

  defp to_markdown({"p", _attrs, children}) do
    Floki.text(children)
  end

  defp to_markdown({"ul", _attrs, children}) do
    children
    |> Enum.filter(fn el -> match?({"li", _, _}, el) end)
    |> Enum.map_join("\n", fn {"li", _, li_children} -> "- " <> Floki.text(li_children) end)
  end

  defp to_markdown({"ol", _attrs, children}) do
    children
    |> Enum.filter(fn el -> match?({"li", _, _}, el) end)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {{"li", _, li_children}, i} ->
      "#{i}. " <> Floki.text(li_children)
    end)
  end

  defp to_markdown({"blockquote", _attrs, children}) do
    "> " <> Floki.text(children)
  end

  defp to_markdown({"pre", _attrs, children}) do
    code = Floki.text(children)
    "```\n" <> code <> "\n```"
  end

  defp to_markdown({"code", _attrs, children}) do
    "`" <> Floki.text(children) <> "`"
  end

  defp to_markdown({"a", attrs, children}) do
    text = Floki.text(children)
    href = Floki.attribute(attrs, "href") |> List.first() || ""
    "[#{text}](#{href})"
  end

  defp to_markdown({"img", attrs, _}) do
    alt = Floki.attribute(attrs, "alt") |> List.first() || ""
    src = Floki.attribute(attrs, "src") |> List.first() || ""
    "![#{alt}](#{src})"
  end

  defp to_markdown({"strong", _attrs, children}) do
    "**" <> Floki.text(children) <> "**"
  end

  defp to_markdown({"em", _attrs, children}) do
    "*" <> Floki.text(children) <> "*"
  end

  defp to_markdown({"br", _, _}), do: "\n"

  defp to_markdown({_tag, _attrs, children}) do
    Floki.text(children)
  end

  defp to_markdown(text) when is_binary(text), do: text

  # Normalize whitespace: collapse multiple spaces/newlines
  defp normalize_whitespace(text) do
    text
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end
end
