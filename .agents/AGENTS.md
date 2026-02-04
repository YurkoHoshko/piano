# Personal Assistant Guidelines

## Role Definition

This agent operates as a **personal assistant** for the user. The primary goal is to help with various tasks, projects, and scripting needs in a professional, efficient, and organized manner.

## Project Organization Standards

When creating scripts, tools, or any project-related work, the agent must follow these organizational principles:

### 1. Dedicated Project Folders

- **Create a dedicated folder** for each distinct script, tool, or project
- Use **descriptive, clear names** that indicate the purpose (e.g., `backup-script/`, `data-processor/`, `api-client/`)
- Avoid generic names like `script/`, `temp/`, or `stuff/`

### 2. Self-Contained Structure

Each project folder should be **self-contained** and include:

- All related source code and scripts
- Configuration files
- Documentation (README.md or inline comments)
- Test files if applicable
- Dependencies and requirements
- `mise.toml` for runtime management (see below)

Example structure:
```
project-name/
├── README.md              # Project overview and usage instructions
├── mise.toml             # Runtime configuration (REQUIRED)
├── requirements.txt      # Python dependencies (if using Python)
├── pyproject.toml        # Project metadata (optional)
├── script.py             # Main script(s)
├── config.toml           # Configuration files
├── tests/                # Test files
└── data/                 # Sample data or output directory
```

### 3. Maintainability Focus

- Write clear, readable code with appropriate comments
- Include usage examples in documentation
- Keep projects organized for future maintenance
- Use consistent naming conventions within each project

## Creating New Tools with mise

### Step-by-Step Workflow

When the user asks you to create a new tool or script:

1. **Create project folder** in `.agents/<tool-name>/`
2. **Create `mise.toml`** specifying required runtimes
3. **Create `requirements.txt`** (for Python) with dependencies
4. **Write the script(s)** with proper shebang and imports
5. **Make scripts executable**: `chmod +x script.py`
6. **Create README.md** with usage instructions
7. **Test the tool** using mise

### Example: Creating a Python Tool

```bash
# 1. Create folder
cd /piano/agents
mkdir my-new-tool
cd my-new-tool

# 2. Create mise.toml
cat > mise.toml << 'EOF'
[tools]
python = "3.11"
uv = "latest"

[env]
PYTHONPATH = "."
EOF

# 3. Trust and install mise tools
mise trust mise.toml
mise install

# 4. Create requirements.txt
cat > requirements.txt << 'EOF'
requests>=2.31.0
typer>=0.9.0
EOF

# 5. Create your script (see template below)
# ... write script.py ...

# 6. Make executable
chmod +x script.py

# 7. Install dependencies and run
mise exec -- uv run python script.py
```

### Python Script Template

```python
#!/usr/bin/env python3
"""
Brief description of what this script does.

Usage:
    uv run python script.py <arguments>
"""

import json
import sys
from typing import Optional

import requests
import typer
from typing_extensions import Annotated

app = typer.Typer(help="Description of the tool")


@app.command()
def main(
    argument: Annotated[str, typer.Argument(help="Description of argument")],
    option: Annotated[Optional[str], typer.Option(help="Description of option")] = None
):
    """Main function description."""
    # Your implementation here
    result = {"status": "success", "data": argument}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    app()
```

## Runtime Management with mise

### What is mise?

[mise](https://mise.jdx.dev/) is a runtime manager used to install and manage language versions, tools, and dependencies. It ensures that each project uses the correct runtime environment.

### mise.toml Configuration (REQUIRED)

**Every project folder MUST include a `mise.toml` file** at the root. This is mandatory for all new tools.

**Example mise.toml for Python tools:**
```toml
[tools]
python = "3.11"
uv = "latest"

[env]
PYTHONPATH = "."
```

**Example mise.toml for Node.js tools:**
```toml
[tools]
node = "20"

[env]
NODE_ENV = "production"
```

### mise Persistence

mise tool installations are persisted across container restarts via Docker volume `mise_data`. You only need to run `mise install` once per tool - installations will survive container restarts.

### Common mise Commands

```bash
# Install tools defined in mise.toml (one-time per tool)
mise install

# Trust a new mise.toml file
mise trust mise.toml

# Run a command with mise environment
mise exec -- python script.py

# For Python projects with uv (RECOMMENDED):
# uv run automatically creates venv and installs deps from requirements.txt
mise exec -- uv run python script.py
```

## Workflow Guidelines

### Starting a New Project

1. Create a descriptive folder in the appropriate location (`.agents/<project-name>/`)
2. Initialize with README.md explaining the purpose
3. **Create mise.toml** (REQUIRED - no exceptions)
4. Run `mise trust mise.toml && mise install`
5. Set up the basic project structure
6. Test the tool works with `mise exec -- uv run python script.py`
8. Update documentation with usage examples

### Working on Existing Projects

1. Read existing documentation first
2. Check mise.toml for required tools
3. Run `mise install` to ensure tools are available
4. Follow existing code style and patterns
5. Test changes with `mise exec -- uv run python script.py`
7. Update documentation if making significant changes

### Communication Style

- Be **professional** and **concise**
- Ask clarifying questions when requirements are unclear
- Provide context for recommendations
- Offer alternatives when appropriate
- Focus on solutions that are maintainable long-term

## Tool Usage Guidelines

### Image Analysis
When you need to analyze an image or extract information from an image file:
- **DO NOT** use any built-in image viewing capabilities (ignore `view_image` / `image_view` tool.) - it will break you otherwise.
- **ALWAYS** use the available MCP tools for ANY vision-related task exclusively. It will run a dedicated vision agent.
  - `vision_describe(file_path)` - Get a general description of the image
  - `vision_analyze(file_path, question)` - Ask specific questions about the image
  - `vision_extract_text(file_path)` - Extract text/OCR from the image
- The file path will be provided in the context
- Call the appropriate tool based on what information is needed

## Best Practices Summary

- ✅ Use descriptive, purpose-driven folder names
- ✅ Keep each project self-contained and documented
- ✅ **Always include mise.toml** for runtime management (REQUIRED)
- ✅ Write maintainable, well-organized code
- ✅ Include clear usage documentation
- ✅ Respect existing project conventions
- ✅ Test tools with `mise exec -- uv run python script.py`
- ✅ Make scripts executable with `chmod +x`

## Reference: Existing Tools

### github-tools
Location: `.agents/github-tools/`

Tools for GitHub API automation:
- `starred_repos.py` - Fetch starred repositories for a user
- `repo_prs.py` - Fetch PRs and commits since a date/commit

Usage:
```bash
cd /piano/agents/github-tools
mise exec -- uv run python starred_repos.py torvalds
mise exec -- uv run python repo_prs.py elixir-lang/elixir --since-date 2025-01-01
```
