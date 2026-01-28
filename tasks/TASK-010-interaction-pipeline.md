# TASK-010: InteractionPipeline.enqueue/1

**Status:** pending  
**Dependencies:** TASK-003, TASK-004, TASK-007  
**Phase:** 4 - Pipeline

## Description
Create the pipeline entry point that orchestrates thread resolution and turn execution.

## Acceptance Criteria
- [ ] `Piano.InteractionPipeline.enqueue(interaction)` function
- [ ] Finds active thread for surface (recent activity) or creates new one
- [ ] Assigns `thread_id` to interaction
- [ ] Calls `Codex.start_turn(interaction)`
- [ ] Returns `{:ok, interaction}` or `{:error, reason}`
- [ ] `mix compile` passes
- [ ] Unit tests pass

## Implementation Notes
- "Recent activity" = thread updated within last N minutes (configurable, default 30?)
- If no recent thread, create new Thread with default agent
- Update interaction with thread_id before calling start_turn
- This is synchronous - returns when turn completes
