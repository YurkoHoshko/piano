# TASK-005: InteractionItem Schema

**Status:** done  
**Dependencies:** TASK-004  
**Phase:** 1 - Core Schemas

## Description
Create the InteractionItem Ash resource to store Codex items within an interaction.

## Acceptance Criteria
- [ ] `Piano.Core.InteractionItem` Ash resource
- [ ] Attributes: `id`, `codex_item_id`, `type`, `payload` (map), `status`
- [ ] Relationships: `belongs_to :interaction`
- [ ] Actions: `:create`, `:complete`, `:list_by_interaction`
- [ ] `mix compile` passes
- [ ] Unit tests pass

## Implementation Notes
- `type` enum: `:user_message`, `:agent_message`, `:reasoning`, `:command_execution`, `:file_change`, `:mcp_tool_call`, `:web_search`
- `payload` stores the full Codex item data as map
- `status` enum: `:started`, `:completed`
