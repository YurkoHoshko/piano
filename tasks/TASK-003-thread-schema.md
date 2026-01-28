# TASK-003: Thread Schema

**Status:** done  
**Dependencies:** TASK-001, TASK-002  
**Phase:** 1 - Core Schemas

## Description
Create the Thread Ash resource to represent conversations, linking to Codex threads.

## Acceptance Criteria
- [ ] `Piano.Core.Thread` Ash resource
- [ ] Attributes: `id`, `codex_thread_id`, `status` (:active/:archived), timestamps
- [ ] Relationships: `has_many :interactions`, `belongs_to :agent`, `belongs_to :surface`
- [ ] Actions: `:create`, `:read`, `:archive`, `:find_recent_for_surface`
- [ ] `mix compile` passes
- [ ] Unit tests pass

## Implementation Notes
- `codex_thread_id` stores the ID from Codex app-server
- `:find_recent_for_surface` should find threads for a surface updated within X minutes
- Status transitions: active → archived
