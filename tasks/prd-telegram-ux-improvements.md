# PRD: Telegram UX Improvements

## Introduction

Improve the Telegram bot experience with better message handling, reply threading, and tool visibility. This includes replying to specific user messages, consolidating bot responses into a single updating message, adding message status tracking for ordered processing, and integrating AgentSkills for extensibility.

## Goals

- Reply to user messages using Telegram's `reply_to_message_id` for clear conversation threading
- Consolidate all bot output into a single message that updates as the agent progresses
- Process messages in order (FIFO) within a session to prevent race conditions
- Display tool calls in expandable blockquotes for cleaner final responses
- Add skill loading tool using AgentSkills format from `.piano/skills/`

## User Stories

### US-001: Reply to user message
**Description:** As a user, I want the bot's response to appear as a reply to my message so I can easily see which response corresponds to which question.

**Acceptance Criteria:**
- [ ] Bot response uses `reply_to_message_id` pointing to the user's original message
- [ ] Works in both direct messages and group chats
- [ ] Placeholder "Processing..." message also replies to the user's message
- [ ] `mix compile` passes

### US-002: Single updating response message
**Description:** As a user, I want to receive only one message from the bot that updates as it works, instead of multiple separate messages.

**Acceptance Criteria:**
- [ ] Bot sends one placeholder message and edits it as processing progresses
- [ ] Tool call progress updates the same message (not new messages)
- [ ] Final response replaces the placeholder in the same message
- [ ] Long responses (>4096 chars) are split only when necessary, using edit for first chunk
- [ ] `mix compile` passes

### US-003: Session-level message queue
**Description:** As a developer, I need to track pending messages per session so they are processed in order.

**Acceptance Criteria:**
- [ ] Add `pending_message_id` field to Session tracking the currently processing user message
- [ ] Use existing GenStage pipeline for message queue (no new GenServers)
- [ ] New messages wait until current message processing completes
- [ ] Messages are processed FIFO (first in, first out)
- [ ] When message is queued, send notification: "⏳ Your message is queued, please wait..."
- [ ] `mix compile` passes

### US-003a: Cancel reply on message deletion
**Description:** As a user, I want to cancel a pending reply by deleting my message.

**Acceptance Criteria:**
- [ ] Bot listens for `message_delete` Telegram updates
- [ ] If deleted message is currently processing, cancel the request
- [ ] If deleted message is queued, remove it from queue
- [ ] No queue depth limit (users can send as many messages as they want)
- [ ] `mix compile` passes

### US-004: Tool calls in expandable blockquote
**Description:** As a user, I want tool calls to appear in a collapsible section so the response is clean but I can see details if needed.

**Acceptance Criteria:**
- [ ] Final response includes tool calls wrapped in `<blockquote expandable>` HTML tag
- [ ] Blockquote has header: "🔧 Tool Calls"
- [ ] Tool calls show name and key arguments (path, command, url, query)
- [ ] Blockquote appears after the main response content
- [ ] Preview shows first few tool calls, rest visible on expand
- [ ] `mix compile` passes

### US-005: Skill discovery and loading
**Description:** As a developer, I want the agent to discover and load skills from `.piano/skills/` directory.

**Acceptance Criteria:**
- [ ] On startup, scan `.piano/skills/` for directories containing `SKILL.md`
- [ ] Parse YAML frontmatter from each `SKILL.md` to extract name and description
- [ ] Store discovered skills in memory (ETS or Agent state)
- [ ] Provide list of available skills to the LLM in system prompt
- [ ] `mix compile` passes

### US-006: Load skill tool
**Description:** As an agent, I want a tool to load a skill's full instructions so I can follow specialized workflows.

**Acceptance Criteria:**
- [ ] Add `load_skill` tool that accepts skill name as argument
- [ ] Tool reads full `SKILL.md` content and returns it
- [ ] Tool validates skill exists before loading
- [ ] Tool returns error if skill not found
- [ ] Loaded skill instructions are injected into conversation context
- [ ] `mix compile` passes

## Functional Requirements

- FR-1: Store user's `message_id` when receiving Telegram text message
- FR-2: Pass `reply_to_message_id` option to all `API.send_message` calls for responses
- FR-3: Pass `reply_to_message_id` option to `API.edit_message_text` calls
- FR-4: Add queue mechanism to Session for pending user messages
- FR-5: Process queued messages sequentially after current response completes
- FR-6: Format tool calls using `<blockquote expandable>` HTML with parse_mode "HTML"
- FR-7: Combine tool calls section with main response in single message when possible
- FR-8: Scan `.piano/skills/*/SKILL.md` on application start
- FR-9: Parse YAML frontmatter (between `---` delimiters) for skill metadata
- FR-10: Register `load_skill` tool with LLM tool definitions
- FR-11: Return skill content when `load_skill` tool is called

## Non-Goals

- No downtime message recovery (messages received while bot is down are not processed)
- No remote skill registry (agentskills.io API) - local filesystem only
- No skill validation beyond checking SKILL.md exists
- No automatic skill activation based on user message content
- No skill caching or hot-reloading (restart required for new skills)

## Technical Considerations

- Use existing GenStage pipeline for message queue (no new GenServers)
- Skill discovery happens in `Application.start/2` within existing pipeline
- YAML parsing via `YamlElixir` (check if already a dependency, else add)
- Tool calls formatting must escape HTML entities (`&`, `<`, `>`)
- Handle Telegram `edited_message` or deletion events for queue cancellation
- Existing `send_or_edit` function needs `reply_to_message_id` support

## Success Metrics

- Bot never sends more than 2 messages per user request (1 response + 1 tool calls if needed)
- Responses always visually threaded to user's question
- No race conditions when user sends multiple messages quickly
- Skills discoverable and loadable by agent

## Open Questions

- What should the queued notification message say exactly? (proposed: "⏳ Your message is queued, please wait...")
- Should the queue notification be a reply to the queued message, or a standalone message?
