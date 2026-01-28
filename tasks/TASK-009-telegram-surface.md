# TASK-009: Telegram Surface

**Status:** pending  
**Dependencies:** TASK-008  
**Phase:** 3 - Surface Protocol

## Description
Implement the Telegram Surface following the Surface behaviour.

## Acceptance Criteria
- [ ] `Piano.Surface.Telegram` implements `Piano.Surface`
- [ ] `handle_event` for `:turn_started` → sends typing indicator
- [ ] `handle_event` for `:agent_message_delta` → accumulates text (or streams via edit)
- [ ] `handle_event` for `:turn_completed` → sends final message
- [ ] `handle_event` for `:approval_required` → sends inline keyboard, waits for callback, returns decision
- [ ] `send_message/2` sends via Telegram API
- [ ] `mix compile` passes
- [ ] Unit tests pass

## Implementation Notes
- Use Req for Telegram Bot API calls
- Surface.identifier is the chat_id
- For streaming, can edit message periodically or just send final
- Inline keyboard for approvals: two buttons "✅ Accept" / "❌ Decline"
- Need to track pending approval requests to match callback_query
