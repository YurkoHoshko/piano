# TASK-007: Codex.start_turn/1

**Status:** pending  
**Dependencies:** TASK-006, TASK-004, TASK-005  
**Phase:** 2 - Codex Integration

## Description
Implement the main function to start a Codex turn for an interaction and stream events.

## Acceptance Criteria
- [ ] `Piano.Codex.start_turn(interaction)` function
- [ ] Looks up thread's codex_thread_id (or creates via thread/start)
- [ ] Calls `turn/start` with agent's cwd, model, sandbox_policy
- [ ] Streams events, for each calls `Surface.handle_event(surface, interaction, event)`
- [ ] On `item/started` → creates InteractionItem
- [ ] On `item/completed` → updates InteractionItem status
- [ ] On `turn/completed` → updates Interaction status and response
- [ ] On approval request → calls `Surface.handle_event` with approval event, waits for response
- [ ] Returns `{:ok, interaction}` or `{:error, reason}`
- [ ] `mix compile` passes
- [ ] Unit tests pass

## Implementation Notes
- Load interaction with thread and agent preloaded
- If thread has no codex_thread_id, call `thread/start` first
- Map agent.sandbox_policy to Codex sandboxPolicy format
- Extract final response text from agentMessage item
- Approval handling is synchronous - block until Surface returns decision
