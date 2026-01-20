#!/usr/bin/env python3
"""Simple DuckDuckGo search script.

This script performs a quick web search on DuckDuckGo and prints a short
summary of the top results. It uses DuckDuckGo's "lite" HTML endpoint which
does not require an API key and is straightforward to scrape.

Usage:
    python search_duckduckgo.py "Elixir programming"

The output will list the title and snippet of the first few results.
"""

import argparse
import sys
import requests
from bs4 import BeautifulSoup

DUCKDUCKGO_SEARCH_URL = "https://duckduckgo.com/html/"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def fetch_results(query: str) -> str:
    """Query DuckDuckGo and return the HTML of the results page.

    Parameters
    ----------
    query : str
        The search string.

    Returns
    -------
    str
        Raw HTML returned by DuckDuckGo.
    """
    params = {"q": query}
    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) DuckDuckGoScript/1.0",
    }
    try:
        r = requests.get(DUCKDUCKGO_SEARCH_URL, params=params, headers=headers, timeout=10)
        r.raise_for_status()
    except requests.RequestException as exc:
        print(f"Error querying DuckDuckGo: {exc}", file=sys.stderr)
        sys.exit(1)
    return r.text


def parse_results(html: str, max_results: int = 5):
    """Parse the DuckDuckGo HTML and yield result tuples.

    Each result is a tuple ``(title, link, snippet)``.
    """
    soup = BeautifulSoup(html, "html.parser")
    results = []
    for result in soup.find_all("div", class_="result__body")[:max_results]:
        # Title and link
        link_tag = result.find("a", class_="result__a")
        if not link_tag:
            continue
        title = link_tag.get_text(strip=True)
        link = link_tag.get("href")
        # Snippet – the paragraph following the title
        snippet_tag = result.find("a", class_="result__snippet")
        snippet = snippet_tag.get_text(strip=True) if snippet_tag else ""
        results.append((title, link, snippet))
    return results


def main():
    parser = argparse.ArgumentParser(description="DuckDuckGo search and summarise.")
    parser.add_argument("query", help="Search query string")
    parser.add_argument("-n", "--number", type=int, default=5,
                        help="Number of results to display (default 5)")
    args = parser.parse_args()

    html = fetch_results(args.query)
    results = parse_results(html, max_results=args.number)

    if not results:
        print("No results found.")
        return

    for idx, (title, link, snippet) in enumerate(results, start=1):
        print(f"{idx}. {title}")
        print(f"   Link: {link}")
        if snippet:
            print(f"   {snippet}")
        print()


if __name__ == "__main__":
    main()

