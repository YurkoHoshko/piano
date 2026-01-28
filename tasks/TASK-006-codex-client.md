# TASK-006: Codex Client

**Status:** pending  
**Dependencies:** none  
**Phase:** 2 - Codex Integration

## Description
Create a GenServer client wrapping the `codex app-server` process for JSON-RPC communication.

## Acceptance Criteria
- [ ] `Piano.Codex.Client` GenServer wrapping `codex app-server` process
- [ ] JSON-RPC 2.0 over stdio (JSONL)
- [ ] `initialize/1` handshake on start
- [ ] Supervised, restarts on crash
- [ ] `mix compile` passes
- [ ] Unit tests pass

## Implementation Notes
- Spawn `codex app-server` via Port
- Send/receive JSONL (one JSON object per line)
- Must send `initialize` request then `initialized` notification before other calls
- Handle bidirectional: we send requests, server sends requests (approvals) and notifications
- Track request IDs for matching responses
- Use Registry or similar for routing notifications to callers
