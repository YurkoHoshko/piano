# TASK-011: Mock LLM API Server

**Status:** pending  
**Dependencies:** none  
**Phase:** 5 - Test Harness

## Description
Create a mock OpenAI-compatible API server for predictable Codex testing.

## Acceptance Criteria
- [ ] `Piano.TestHarness.MockLLMServer` Plug-based server
- [ ] OpenAI chat completions endpoint (`POST /v1/chat/completions`)
- [ ] Configurable response sequences
- [ ] Supports tool calls in responses
- [ ] `mix compile` passes
- [ ] Unit tests pass

## Implementation Notes
- Use Plug.Router
- Start on random available port
- Queue of responses that get consumed in order
- Support streaming (SSE) and non-streaming responses
- Log requests for test assertions
- Helper functions: `expect_response(text)`, `expect_tool_call(name, args)`
