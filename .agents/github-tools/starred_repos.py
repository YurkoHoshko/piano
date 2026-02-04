#!/usr/bin/env python3
"""
GitHub Starred Repos Fetcher

Returns a list of repositories starred by a GitHub user.
Output is formatted as JSON and printed to stdout.
"""

import json
import os
import sys
import urllib.request
import urllib.error
import urllib.parse
from typing import List, Dict, Optional

import typer
from typing_extensions import Annotated

app = typer.Typer(help="Fetch repositories starred by a GitHub user")

GITHUB_API_BASE = "https://api.github.com"


def get_github_token(token: Optional[str] = None) -> Optional[str]:
    """Get GitHub token from argument or environment variable."""
    return token or os.environ.get("GITHUB_TOKEN")


def fetch_starred_repos(username: str, token: Optional[str] = None) -> List[Dict]:
    """
    Fetch all starred repositories for a given user.

    Args:
        username: GitHub username
        token: Optional GitHub personal access token for higher rate limits

    Returns:
        List of repository dictionaries with relevant fields
    """
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "github-tools-starred-repos",
    }
    if token:
        headers["Authorization"] = f"token {token}"

    repos = []
    page = 1
    per_page = 100  # Max allowed by GitHub API

    while True:
        url = f"{GITHUB_API_BASE}/users/{username}/starred"
        params = {
            "page": page,
            "per_page": per_page,
            "sort": "updated",
            "direction": "desc",
        }

        try:
            query = urllib.parse.urlencode(params)
            full_url = f"{url}?{query}"
            req = urllib.request.Request(full_url, headers=headers)
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = resp.read().decode("utf-8")
                data = json.loads(body)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                print(f"Error: User '{username}' not found", file=sys.stderr)
                sys.exit(1)
            elif e.code == 403:
                print(
                    f"Error: Rate limit exceeded. Use --token for higher limits.",
                    file=sys.stderr,
                )
                sys.exit(1)
            else:
                print(f"Error: HTTP {e.code}", file=sys.stderr)
                sys.exit(1)
        except urllib.error.URLError as e:
            print(f"Error: Failed to fetch data: {e.reason}", file=sys.stderr)
            sys.exit(1)

        if not data:
            break

        for repo in data:
            repos.append(
                {
                    "name": repo.get("name"),
                    "full_name": repo.get("full_name"),
                    "owner": repo.get("owner", {}).get("login"),
                    "description": repo.get("description"),
                    "url": repo.get("html_url"),
                    "stars": repo.get("stargazers_count"),
                    "language": repo.get("language"),
                    "created_at": repo.get("created_at"),
                    "updated_at": repo.get("updated_at"),
                    "pushed_at": repo.get("pushed_at"),
                }
            )

        if len(data) < per_page:
            break
        page += 1

    # The error handling above already exits on failure, so nothing more needed.

    return repos


@app.command()
def main(
    username: Annotated[
        str, typer.Argument(help="GitHub username to fetch starred repos for")
    ],
    token: Annotated[
        Optional[str],
        typer.Option(help="GitHub personal access token (or set GITHUB_TOKEN env var)"),
    ] = None,
):
    """Fetch and output starred repositories for a user."""
    github_token = get_github_token(token)

    repos = fetch_starred_repos(username, github_token)

    output = {"username": username, "total_count": len(repos), "repositories": repos}

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    app()
