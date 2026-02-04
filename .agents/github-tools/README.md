# GitHub Tools

Python scripts for GitHub API automation using UV (via mise) for dependency management.

## Scripts

1. **starred_repos.py** - Get list of repositories starred by a GitHub user
2. **repo_prs.py** - Get pull requests with commits since a date or commit

## Setup

This project uses [mise](https://mise.jdx.dev/) to manage Python and UV versions.

```bash
# Install tools (Python 3.11 and UV)
mise install

# Install dependencies
uv pip install -r requirements.txt
```

## Usage

### Get Starred Repos
```bash
uv run starred_repos.py <username> [--token GITHUB_TOKEN]
```

### Get Recent PRs
```bash
uv run repo_prs.py <owner/repo> --since-date 2024-01-01 [--token GITHUB_TOKEN]
# or
uv run repo_prs.py <owner/repo> --since-commit <COMMIT_SHA> [--token GITHUB_TOKEN]
```

## Environment Variables

- `GITHUB_TOKEN` - GitHub personal access token (required for higher rate limits)

## Integration with Piano Scheduler

These scripts can be used with `Piano.Scheduler` to create recurring GitHub summaries:

1. Fetch starred repos from users of interest
2. Monitor PR activity in tracked repositories
3. Generate periodic digests
