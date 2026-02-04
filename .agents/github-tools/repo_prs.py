#!/usr/bin/env python3
"""
GitHub Repository PR Fetcher

Returns a list of pull requests with commits since a certain date or commit.
Output is formatted as JSON and printed to stdout.
"""

import json
import os
import sys
from datetime import datetime
from typing import List, Dict, Optional

import requests
import typer
from dateutil import parser as date_parser
from typing_extensions import Annotated

app = typer.Typer(help="Fetch PRs with commits since a date or commit")

GITHUB_API_BASE = "https://api.github.com"


def get_github_token(token: Optional[str] = None) -> Optional[str]:
    """Get GitHub token from argument or environment variable."""
    return token or os.environ.get("GITHUB_TOKEN")


def fetch_commits_since(
    repo: str,
    since_date: Optional[str] = None,
    since_commit: Optional[str] = None,
    token: Optional[str] = None,
) -> List[Dict]:
    """
    Fetch commits since a date or specific commit.

    Args:
        repo: Repository in format "owner/repo"
        since_date: ISO 8601 date string to fetch commits after
        since_commit: Commit SHA to fetch commits after
        token: Optional GitHub personal access token

    Returns:
        List of commit dictionaries
    """
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "github-tools-repo-prs",
    }

    if token:
        headers["Authorization"] = f"token {token}"

    # If since_commit is provided, get its date first
    if since_commit and not since_date:
        commit_url = f"{GITHUB_API_BASE}/repos/{repo}/commits/{since_commit}"
        try:
            response = requests.get(commit_url, headers=headers, timeout=30)
            response.raise_for_status()
            commit_data = response.json()
            since_date = commit_data.get("commit", {}).get("committer", {}).get("date")
        except requests.exceptions.RequestException as e:
            print(f"Error: Failed to fetch commit {since_commit}: {e}", file=sys.stderr)
            sys.exit(1)

    commits = []
    page = 1
    per_page = 100

    while True:
        url = f"{GITHUB_API_BASE}/repos/{repo}/commits"
        params = {
            "page": page,
            "per_page": per_page,
            "sha": "HEAD",  # Default branch
        }

        if since_date:
            params["since"] = since_date

        response = None
        try:
            response = requests.get(url, headers=headers, params=params, timeout=30)
            response.raise_for_status()

            data = response.json()
            if not data:
                break

            for commit in data:
                commit_info = commit.get("commit", {})
                author = commit_info.get("author", {})
                committer = commit_info.get("committer", {})

                commits.append(
                    {
                        "sha": commit.get("sha"),
                        "message": commit_info.get("message"),
                        "author": commit.get("author", {}).get("login")
                        if commit.get("author")
                        else author.get("name"),
                        "author_email": author.get("email"),
                        "author_date": author.get("date"),
                        "committer": commit.get("committer", {}).get("login")
                        if commit.get("committer")
                        else committer.get("name"),
                        "commit_date": committer.get("date"),
                        "url": commit.get("html_url"),
                    }
                )

            if len(data) < per_page:
                break

            page += 1

        except requests.exceptions.HTTPError as e:
            if response and response.status_code == 404:
                print(f"Error: Repository '{repo}' not found", file=sys.stderr)
                sys.exit(1)
            elif response and response.status_code == 403:
                print(
                    f"Error: Rate limit exceeded. Use --token for higher limits.",
                    file=sys.stderr,
                )
                sys.exit(1)
            else:
                print(f"Error: HTTP {e}", file=sys.stderr)
                sys.exit(1)
        except requests.exceptions.RequestException as e:
            print(f"Error: Failed to fetch commits: {e}", file=sys.stderr)
            sys.exit(1)

    return commits


def fetch_prs_with_commits(
    repo: str, commits: List[Dict], token: Optional[str] = None
) -> List[Dict]:
    """
    Fetch PRs that contain the given commits.

    Args:
        repo: Repository in format "owner/repo"
        commits: List of commit dictionaries
        token: Optional GitHub personal access token

    Returns:
        List of PR dictionaries with associated commits
    """
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "github-tools-repo-prs",
    }

    if token:
        headers["Authorization"] = f"token {token}"

    # Get all PRs
    prs = []
    page = 1
    per_page = 100

    while True:
        url = f"{GITHUB_API_BASE}/repos/{repo}/pulls"
        params = {
            "state": "all",
            "page": page,
            "per_page": per_page,
            "sort": "updated",
            "direction": "desc",
        }

        try:
            response = requests.get(url, headers=headers, params=params, timeout=30)
            response.raise_for_status()

            data = response.json()
            if not data:
                break

            prs.extend(data)

            if len(data) < per_page:
                break

            page += 1

        except requests.exceptions.RequestException as e:
            print(f"Warning: Failed to fetch PRs: {e}", file=sys.stderr)
            break

    # For each commit, try to find associated PR
    commit_shas = {c["sha"] for c in commits}
    pr_commits_map = {}

    for pr in prs:
        pr_number = pr.get("number")

        # Fetch commits for this PR
        commits_url = f"{GITHUB_API_BASE}/repos/{repo}/pulls/{pr_number}/commits"
        try:
            response = requests.get(commits_url, headers=headers, timeout=30)
            response.raise_for_status()
            pr_commit_list = response.json()

            # Check if any of these commits are in our list
            matching_commits = []
            for pr_commit in pr_commit_list:
                pr_sha = pr_commit.get("sha")
                if pr_sha in commit_shas:
                    matching_commits.append(pr_sha)

            if matching_commits:
                pr_commits_map[pr_number] = {
                    "pr": pr,
                    "matching_commits": matching_commits,
                }

        except requests.exceptions.RequestException:
            continue

    # Build result
    result_prs = []
    for pr_number, data in pr_commits_map.items():
        pr = data["pr"]
        pr_commits = data["matching_commits"]

        # Get full commit details
        associated_commits = [c for c in commits if c["sha"] in pr_commits]

        result_prs.append(
            {
                "number": pr.get("number"),
                "title": pr.get("title"),
                "state": pr.get("state"),
                "user": pr.get("user", {}).get("login"),
                "url": pr.get("html_url"),
                "created_at": pr.get("created_at"),
                "updated_at": pr.get("updated_at"),
                "merged_at": pr.get("merged_at"),
                "closed_at": pr.get("closed_at"),
                "body": pr.get("body"),
                "commits_count": len(associated_commits),
                "commits": associated_commits,
            }
        )

    # Sort by updated_at descending
    result_prs.sort(key=lambda x: x.get("updated_at", ""), reverse=True)

    return result_prs


@app.command()
def main(
    repo: Annotated[str, typer.Argument(help="Repository in format 'owner/repo'")],
    since_date: Annotated[
        Optional[str],
        typer.Option(help="Fetch commits/PRs since this date (YYYY-MM-DD)"),
    ] = None,
    since_commit: Annotated[
        Optional[str], typer.Option(help="Fetch commits/PRs since this commit SHA")
    ] = None,
    token: Annotated[
        Optional[str],
        typer.Option(help="GitHub personal access token (or set GITHUB_TOKEN env var)"),
    ] = None,
    include_prs: Annotated[
        bool, typer.Option(help="Include PRs associated with commits")
    ] = True,
):
    """Fetch PRs and commits since a date or commit."""

    if not since_date and not since_commit:
        print(
            "Error: Must provide either --since-date or --since-commit", file=sys.stderr
        )
        sys.exit(1)

    github_token = get_github_token(token)

    # Convert date format if needed
    if since_date:
        try:
            # Parse to ensure valid date, then format as ISO 8601
            parsed_date = date_parser.parse(since_date)
            since_date = parsed_date.isoformat()
        except ValueError as e:
            print(f"Error: Invalid date format: {e}", file=sys.stderr)
            sys.exit(1)

    print(f"Fetching commits from {repo}...", file=sys.stderr)

    commits = fetch_commits_since(repo, since_date, since_commit, github_token)

    if not commits:
        print("No commits found since the specified date/commit", file=sys.stderr)
        output = {
            "repository": repo,
            "since_date": since_date,
            "since_commit": since_commit,
            "total_commits": 0,
            "total_prs": 0,
            "commits": [],
            "pull_requests": [],
        }
        print(json.dumps(output, indent=2))
        return

    prs = []
    if include_prs:
        print(f"Fetching associated PRs...", file=sys.stderr)
        prs = fetch_prs_with_commits(repo, commits, github_token)

    output = {
        "repository": repo,
        "since_date": since_date,
        "since_commit": since_commit,
        "total_commits": len(commits),
        "total_prs": len(prs),
        "commits": commits,
        "pull_requests": prs,
    }

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    app()
