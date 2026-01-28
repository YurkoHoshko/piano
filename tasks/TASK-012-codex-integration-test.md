# TASK-012: Codex Integration Test

**Status:** pending  
**Dependencies:** TASK-006, TASK-007, TASK-011  
**Phase:** 5 - Test Harness

## Description
Create E2E tests for the Codex flow using real app-server with mock LLM backend.

## Acceptance Criteria
- [ ] Test: message → Codex → mock API → response → interaction completed
- [ ] Test: approval flow with mock tool call
- [ ] Test: turn interruption
- [ ] Uses real Codex app-server with mock API backend
- [ ] `mix test` passes

## Implementation Notes
- Start MockLLMServer, get port
- Configure Codex to use `http://localhost:{port}` as API endpoint
- Create test Surface, Thread, Interaction
- Call `Codex.start_turn` and verify results
- For approval test: mock returns tool_call, verify approval event, respond, verify completion
