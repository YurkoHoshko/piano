#!/usr/bin/env elixir
# #!/usr/bin/env elixir
# A simple DuckDuckGo search script
# Author: ChatGPT
# Usage: elixir search_duckduckgo.exs "query" [--number N]

# Ensure dependencies
Mix.install([{:httpoison, "~> 1.8"}, {:floki, "~> 0.32"}])

# Parse command‑line arguments
args = System.argv()

{query, opts} = case Enum.take(args, 2) do
  [q] -> {q, []}
  [q, "--number", n | _] -> {q, [number: String.to_integer(n)]}
  _ ->
    IO.puts("Usage: elixir search_duckduckgo.exs \"query\" [--number N]")
    System.halt(1)
end

# Default number of results
number = Keyword.get(opts, :number, 10)

# DuckDuckGo HTML search URL
search_url = "https://duckduckgo.com/html/?q=" <> URI.encode_www_form(query)

# Fetch the page
{:ok, %{status_code: 200, body: html}} = HTTPoison.get(search_url)

# Parse the results
results =
  html
  |> Floki.parse_document!
  |> Floki.find("a.result__a")
  |> Enum.take(number)
  |> Enum.map(fn {"a", attrs, [title]} ->
    link = Enum.find_value(attrs, fn {"href", href} -> href end)
    snippet =
      html
      |> Floki.parse_document!
      |> Floki.find("a.result__a[\"href\"=" <> link <> "] ~ .result__snippet")
      |> Floki.text(" ")
      |> String.trim()
    {title, link, snippet}
  end)

# Print results
Enum.each(results, fn {title, link, snippet} ->
  IO.puts("\nTitle: #{title}")
  IO.puts("Link: #{link}")
  IO.puts("Snippet: #{snippet}")
end)

IO.puts("\nFound #{length(results)} result(s).")

# ------------------------------------------------------------
# A lightweight DuckDuckGo search tool written in Elixir.
# ------------------------------------------------------------
#
# Dependencies
#   * HTTPoison – HTTP client
#   * Floki     – HTML parser
#
# Install with:
#   mix escript.install hex :httpoison
#   mix escript.install hex :floki
#
# Usage:
#   elixir search_duckduckgo.exs "search query" [--number N] [--help]
#
# ------------------------------------------------------------

# --- Configuration ------------------------------------------------
search_url = "https://duckduckgo.com/html/"
default_n = 5

# --- Helper Functions --------------------------------------------
@doc """
  Sends a GET request to DuckDuckGo and returns the raw HTML.
"""
@spec fetch_results(String.t()) :: String.t()
defp fetch_results(query) do
  headers = [{"User-Agent", "DuckDuckGoElixirScript/1.0"}]
  # Build the query string
  url = search_url <> "?q=" <> URI.encode_www_form(query)

  case HTTPoison.get(url, headers, timeout: 10_000, recv_timeout: 10_000) do
    {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
      body

    {:ok, %HTTPoison.Response{status_code: code}} ->
      IO.puts("Error: Received status #{code}", :stderr)
      System.halt(1)

    {:error, reason} ->
      IO.puts("Error querying DuckDuckGo: #{inspect(reason)}", :stderr)
      System.halt(1)
  end
end

@doc """
  Parses the HTML from DuckDuckGo and extracts `{title, link, snippet}` tuples.
  Limits the results to `max_results`.
"""
@spec parse_results(String.t(), non_neg_integer()) :: list()
defp parse_results(html, max_results) do
  html
  |> Floki.parse_document!()
  |> Floki.find("div.result__body")
  |> Enum.take(max_results)
  |> Enum.map(fn node ->
    # Title & link
    title = node |> Floki.find("a.result__a") |> Floki.text("", true)
    link  = node |> Floki.find("a.result__a") |> Floki.attribute("href") |> List.first()

    # Snippet (the paragraph following the title)
    snippet =
      node
      |> Floki.find("a.result__snippet")
      |> Floki.text("", true)

    {title, link, snippet}
  end)
end

# --- CLI entry point -----------------------------------------------
{opts, args, _} =
  OptionParser.parse(System.argv(),
    switches: [number: :integer, help: :boolean],
    aliases:  [n: :number, h: :help]
  )

if opts[:help] || length(args) < 1 do
  IO.puts("""
  Usage: elixir search_duckduckgo.exs \"query\" [--number N] [--help]
  Options:
    --number N, -n N   Number of results to display (default #{ default_n })
    --help, -h         Show this help message
  """)
  System.halt(0)
end

query = Enum.join(args, " ")
count = opts[:number] || default_n

# --- Main workflow -----------------------------------------------
html = fetch_results(query)
results = parse_results(html, count)

if results == [] do
  IO.puts("No results found.")
  System.halt(0)
end

results
|> Enum.with_index(1)
|> Enum.each(fn {{title, link, snippet}, idx} ->
  IO.puts("#{idx}. #{title}")
  IO.puts("   Link: #{link}")
  if snippet != "" do
    IO.puts("   #{snippet}")
  end
  IO.puts("")
end)

# ------------------------------------------------------------
# End of script
# ------------------------------------------------------------
