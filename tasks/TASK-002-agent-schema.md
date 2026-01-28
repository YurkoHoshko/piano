# TASK-002: Agent Schema

**Status:** done  
**Dependencies:** none  
**Phase:** 1 - Core Schemas

## Description
Create the Agent Ash resource to represent AI assistants with their Codex configuration.

## Acceptance Criteria
- [ ] `Piano.Core.Agent` Ash resource
- [ ] Attributes: `id`, `name`, `model`, `workspace_path` (folder with AGENTS.md), `sandbox_policy`, `auto_approve_policy`
- [ ] Actions: `:create`, `:read`, `:update`, `:list`, `:get_default`
- [ ] `mix compile` passes
- [ ] Unit tests pass

## Implementation Notes
- `workspace_path` points to folder containing AGENTS.md for Codex instructions
- `sandbox_policy` enum: `:read_only`, `:workspace_write`, `:full_access`
- `auto_approve_policy` enum: `:none`, `:safe`, `:all`
- `model` is string like "o3" or "gpt-4.1"
- Need a way to mark one agent as default
