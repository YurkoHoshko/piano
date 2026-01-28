# TASK-004: Interaction Schema

**Status:** done  
**Dependencies:** TASK-001, TASK-003  
**Phase:** 1 - Core Schemas

## Description
Create the Interaction Ash resource to represent user requests and agent responses.

## Acceptance Criteria
- [ ] `Piano.Core.Interaction` Ash resource
- [ ] Attributes: `id`, `codex_turn_id`, `original_message`, `status` (:pending/:in_progress/:complete/:interrupted/:failed), `response`
- [ ] Relationships: `belongs_to :thread`, `belongs_to :surface`, `has_many :items`
- [ ] Actions: `:create`, `:start`, `:complete`, `:fail`, `:interrupt`
- [ ] `mix compile` passes
- [ ] Unit tests pass

## Implementation Notes
- `codex_turn_id` stores the turn ID from Codex
- `original_message` is the user's input text
- `response` is the final agent response text (nullable until complete)
- Status transitions: pending → in_progress → complete/interrupted/failed
