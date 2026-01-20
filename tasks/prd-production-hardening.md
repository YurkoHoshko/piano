# PRD: Production Hardening & Feature Completeness

## Introduction

Piano is an Elixir-based multi-agent chat system with Telegram and web interfaces. This PRD covers production hardening improvements: structured logging, tool usage fixes, comprehensive testing, additional Telegram commands, persistent chat sessions, migration to ReqLLM, and improved UX with placeholder messages.

## Goals

- Implement structured, configurable logging across all subsystems
- Fix tool usage so models recognize and use available tools
- Add unit tests for persistence layer and E2E tests for web UI
- Expand Telegram bot commands for better user experience
- Persist Telegram chat→thread mappings in the database (remove ETS dependency)
- Migrate LLM client from custom Req implementation to ReqLLM
- Improve Telegram UX with placeholder messages during processing

## User Stories

### US-001: Structured logging with module tagging
**Description:** As a developer, I want organized logs with clear module prefixes so I can quickly identify the source of log entries.

**Acceptance Criteria:**
- [ ] Create `Piano.Logger` module with tagged logging helpers
- [ ] Log format: `[Piano.LLM] Calling model qwen3:32b with 3 messages`
- [ ] Log format: `[Piano.Telegram] Received message from chat_id=123456`
- [ ] Log format: `[Piano.Agents] Executing tool read_file with args...`
- [ ] All existing `Logger.error/info/debug` calls use new tagged format
- [ ] `mix compile` passes without warnings

---

### US-002: Configurable log levels per subsystem
**Description:** As a developer, I want to suppress noisy logs (like HTTP responses) while keeping important ones visible.

**Acceptance Criteria:**
- [ ] Add config option: `config :piano, :log_levels, llm: :info, telegram: :debug, agents: :info`
- [ ] HTTP response bodies from Telegram API are logged at `:debug` level only
- [ ] LLM request/response summaries logged at `:info`, full bodies at `:debug`
- [ ] Default log levels are sensible for production (not too verbose)
- [ ] Document log level configuration in README or config comments

---

### US-003: Investigate and fix tool passing to LLM
**Description:** As a developer, I need to verify tools are correctly passed to the LLM and diagnose why models may not recognize them.

**Acceptance Criteria:**
- [ ] Add debug logging showing exact tool definitions sent to LLM
- [ ] Verify `Piano.LLM.Impl.maybe_add_tools/2` formats tools correctly per OpenAI spec
- [ ] Confirm `tool_choice` parameter is set appropriately (e.g., `"auto"`)
- [ ] Add test case verifying tool definitions in LLM request body
- [ ] Document any model-specific quirks (e.g., some models need specific prompting for tools)

---

### US-004: Implement tool execution loop
**Description:** As a user, I want the agent to actually execute tools when the LLM requests them, returning results back to the conversation.

**Acceptance Criteria:**
- [ ] When LLM response contains `tool_calls`, execute each tool via `ToolRegistry`
- [ ] Append tool results as `role: "tool"` messages to conversation
- [ ] Re-call LLM with updated conversation to get final response
- [ ] Handle tool execution errors gracefully (return error message to LLM)
- [ ] Limit tool call iterations (max 5) to prevent infinite loops
- [ ] Add logging for each tool execution: `[Piano.Agents] Tool read_file returned 1024 bytes`

---

### US-005: Unit tests for Chat.Thread resource
**Description:** As a developer, I want unit tests for Thread persistence to catch regressions.

**Acceptance Criteria:**
- [ ] Test `Thread.create` action creates thread with correct defaults
- [ ] Test `Thread.list` action returns threads sorted by inserted_at
- [ ] Test `Thread.fork` action creates new thread with copied messages up to fork point
- [ ] Test thread title generation/update
- [ ] All tests use `Piano.DataCase` with database isolation
- [ ] `mix test test/piano/chat/thread_test.exs` passes

---

### US-006: Unit tests for Chat.Message resource
**Description:** As a developer, I want unit tests for Message persistence.

**Acceptance Criteria:**
- [ ] Test `Message.create` with all required fields (content, role, source, thread_id)
- [ ] Test `Message.list_by_thread` returns messages for correct thread only
- [ ] Test message roles (:user, :agent, :system, :tool) are properly validated
- [ ] Test message sources (:web, :telegram, :api) are properly validated
- [ ] `mix test test/piano/chat/message_test.exs` passes

---

### US-007: Unit tests for Agents.Agent resource
**Description:** As a developer, I want unit tests for Agent persistence.

**Acceptance Criteria:**
- [ ] Test `Agent.create` with name, model, system_prompt
- [ ] Test `Agent.update_config` updates enabled_tools and enabled_skills
- [ ] Test `Agent.list` returns agents sorted by inserted_at
- [ ] Test validation: name and model are required
- [ ] `mix test test/piano/agents/agent_test.exs` passes

---

### US-008: E2E tests for ChatLive with Wallaby
**Description:** As a developer, I want E2E tests for the web chat interface.

**Acceptance Criteria:**
- [ ] Add `wallaby` dependency to mix.exs (test only)
- [ ] Configure Wallaby with ChromeDriver headless
- [ ] Test: User can send a message and see it appear in chat
- [ ] Test: User can create a new thread via button
- [ ] Test: User can switch between threads in sidebar
- [ ] Test: "Thinking..." indicator appears while waiting for response
- [ ] All E2E tests use mocked LLM (no real API calls)
- [ ] `mix test test/piano_web/live/chat_live_e2e_test.exs` passes

---

### US-009: Add /help command to Telegram bot
**Description:** As a Telegram user, I want a /help command to see all available commands.

**Acceptance Criteria:**
- [ ] `/help` returns formatted list of all commands with descriptions
- [ ] Help text includes: /start, /newthread, /thread, /help, /agents, /switch, /status, /cancel, /history
- [ ] Help text is well-formatted with emoji indicators
- [ ] Command registered in `setup_commands: true` list

---

### US-010: Add /agents command to Telegram bot
**Description:** As a Telegram user, I want to see available agents I can chat with.

**Acceptance Criteria:**
- [ ] `/agents` lists all agents with name and description
- [ ] Shows which agent is currently active for this chat
- [ ] Format: `🤖 AgentName - Description (active)` or `🤖 AgentName - Description`
- [ ] If no agents exist, show helpful message

---

### US-011: Add /switch command to Telegram bot
**Description:** As a Telegram user, I want to switch which agent handles my messages.

**Acceptance Criteria:**
- [ ] `/switch <agent_name>` changes active agent for current chat
- [ ] Agent lookup is case-insensitive
- [ ] If agent not found, show error with available agent names
- [ ] Confirmation message: `✅ Switched to AgentName`
- [ ] Store agent preference per chat_id (in DB, see US-016)

---

### US-012: Add /status command to Telegram bot
**Description:** As a Telegram user, I want to see my current session status.

**Acceptance Criteria:**
- [ ] `/status` shows: current thread ID, active agent, message count in thread
- [ ] Shows thread title if set
- [ ] Shows when thread was created
- [ ] Format is clear and readable

---

### US-013: Add /cancel command to Telegram bot
**Description:** As a Telegram user, I want to cancel a long-running request.

**Acceptance Criteria:**
- [ ] `/cancel` attempts to cancel any in-progress LLM request for this chat
- [ ] If nothing is processing, show "Nothing to cancel"
- [ ] If cancelled, show "⏹️ Request cancelled"
- [ ] Requires tracking active requests per chat_id

---

### US-014: Add /history command to Telegram bot
**Description:** As a Telegram user, I want to see my recent messages in the current thread.

**Acceptance Criteria:**
- [ ] `/history` shows last 10 messages in current thread
- [ ] Format: `You: message content` / `Bot: response content`
- [ ] Truncate long messages to 100 chars with "..."
- [ ] If no messages, show "No messages in this thread yet"

---

### US-015: Add /delete command to Telegram bot
**Description:** As a Telegram user, I want to delete my current thread and start fresh.

**Acceptance Criteria:**
- [ ] `/delete` deletes current thread and all messages
- [ ] Asks for confirmation: "Are you sure? Reply /delete confirm"
- [ ] `/delete confirm` actually deletes
- [ ] After deletion, next message creates new thread
- [ ] Show confirmation: "🗑️ Thread deleted"

---

### US-016: Persist Telegram sessions in database
**Description:** As a developer, I want chat→thread mappings stored in the database so they survive restarts.

**Acceptance Criteria:**
- [ ] Create `Piano.Telegram.Session` Ash resource with: chat_id (integer), thread_id (uuid), agent_id (uuid, optional)
- [ ] Add migration for telegram_sessions table
- [ ] Replace ETS lookups in `SessionMapper` with database queries
- [ ] Remove GenServer from `SessionMapper` (pure module with DB calls)
- [ ] Add unique constraint on chat_id
- [ ] Update tests to not require `start_supervised!(SessionMapper)`
- [ ] `mix ash.migrate` runs successfully

---

### US-017: Add ReqLLM dependency
**Description:** As a developer, I want to add ReqLLM as a dependency for future LLM client migration.

**Acceptance Criteria:**
- [ ] Add `{:req_llm, "~> 1.0"}` to mix.exs deps
- [ ] Run `mix deps.get` successfully
- [ ] Configure ReqLLM for llama-swap (OpenAI-compatible endpoint)
- [ ] Document configuration in config/runtime.exs or config/config.exs

---

### US-018: Create ReqLLM-based LLM client
**Description:** As a developer, I want a new LLM implementation using ReqLLM alongside the existing one.

**Acceptance Criteria:**
- [ ] Create `Piano.LLM.ReqLLMImpl` module implementing `Piano.LLM` behaviour
- [ ] Use ReqLLM's low-level API with custom base_url for llama-swap
- [ ] Support same options as current impl: model, messages, tools
- [ ] Add config flag: `config :piano, :llm_impl, Piano.LLM.ReqLLMImpl`
- [ ] Both implementations coexist (switchable via config)
- [ ] Add test comparing outputs of both implementations

---

### US-019: Verify ReqLLM implementation parity
**Description:** As a developer, I want to verify ReqLLM produces identical results before removing the old client.

**Acceptance Criteria:**
- [ ] Create comparison test that runs same prompt through both implementations
- [ ] Verify response structure matches (content, tool_calls extraction)
- [ ] Verify error handling matches
- [ ] Run manual tests with Telegram and web interfaces
- [ ] Document any behavioral differences

---

### US-020: Remove old LLM implementation
**Description:** As a developer, I want to remove the old custom LLM client after ReqLLM is verified.

**Acceptance Criteria:**
- [ ] Remove `Piano.LLM.Impl` module
- [ ] Update `Piano.LLM` to use ReqLLM directly (no impl switching)
- [ ] Remove any unused Req-related code specific to old impl
- [ ] All existing tests pass
- [ ] `mix compile` passes without warnings

---

### US-021: Send placeholder message on Telegram
**Description:** As a Telegram user, I want to see immediate feedback when my message is being processed.

**Acceptance Criteria:**
- [ ] When user sends message, immediately send "⏳ Processing..." to chat
- [ ] Store the message_id of the placeholder message
- [ ] When LLM response is ready, edit the placeholder message with actual content
- [ ] Use Telegram `editMessageText` API
- [ ] If edit fails (message too old), send new message instead
- [ ] Add `edit_message/3` to `Piano.Telegram.API`

---

### US-022: Handle placeholder message edge cases
**Description:** As a developer, I want robust placeholder handling for edge cases.

**Acceptance Criteria:**
- [ ] If processing takes >30 seconds, update placeholder to "⏳ Still working..."
- [ ] If error occurs, edit placeholder to show error message
- [ ] If user sends /cancel, edit placeholder to "⏹️ Cancelled"
- [ ] Long responses (>4096 chars) are split across multiple messages
- [ ] Markdown formatting preserved where possible

---

## Functional Requirements

- FR-1: `Piano.Logger` module provides `log/3` function with module tag prefix
- FR-2: Log levels are configurable per module via application config
- FR-3: Tools are passed to LLM with correct OpenAI function-calling format
- FR-4: Tool execution loop runs tools and feeds results back to LLM
- FR-5: All Ash resources (Thread, Message, Agent) have unit tests
- FR-6: Wallaby E2E tests cover main chat UI workflows
- FR-7: Telegram bot supports 9 commands: /start, /newthread, /thread, /help, /agents, /switch, /status, /cancel, /history, /delete
- FR-8: `Piano.Telegram.Session` resource persists chat→thread→agent mappings
- FR-9: ReqLLM is used for LLM calls with llama-swap base URL
- FR-10: Telegram sends editable placeholder messages during processing

## Non-Goals

- Real-time streaming of LLM responses to Telegram (not supported well by Telegram API)
- Multi-user authentication/authorization
- Rate limiting or usage quotas
- Support for LLM providers other than llama-swap (yet)
- Telegram inline mode or callback buttons
- Message history export to files

## Technical Considerations

- **Logging:** Use Elixir's built-in Logger with metadata for structured logging
- **Testing:** Wallaby requires ChromeDriver; CI will need headless Chrome setup
- **Database:** Telegram sessions table needs index on chat_id for fast lookups
- **ReqLLM:** Use low-level Req plugin API since llama-swap is OpenAI-compatible
- **Placeholder messages:** Telegram's editMessageText has rate limits; implement backoff

## Success Metrics

- All new tests pass (`mix test` green)
- Logs are clean and filterable by module
- Tools are executed when LLM requests them
- Telegram session survives server restart
- ReqLLM integration works identically to old client
- Users see immediate feedback on Telegram

## Open Questions

- Should /cancel actually kill the LLM request, or just stop waiting for it?
- Should we add /export to export thread as markdown/JSON?
- What's the maximum tool call depth before we force a final response?
- Should placeholder message show elapsed time?
