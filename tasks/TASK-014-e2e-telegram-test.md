# TASK-014: End-to-End Telegram Test

**Status:** pending  
**Dependencies:** TASK-012, TASK-013  
**Phase:** 6 - Telegram Bot

## Description
Create E2E tests for the complete Telegram flow.

## Acceptance Criteria
- [ ] Test: Telegram message → full pipeline → response sent
- [ ] Test: Approval via inline keyboard
- [ ] Uses mock LLM API + mocked Telegram API
- [ ] `mix test` passes

## Implementation Notes
- Mock Telegram API (or use Bypass)
- Simulate incoming update with text message
- Verify Surface/Interaction created
- Verify response sent back via Telegram API mock
- For approval: verify inline keyboard sent, simulate callback_query, verify decision sent to Codex
