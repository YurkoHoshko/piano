# PRD: Piano - Multi-Agent Chat System

## Introduction

Piano is an Elixir-based multi-channel AI assistant system supporting real-time chat via Phoenix LiveView and Telegram. A single user can chat with one or more LLM-powered agents using unified conversation threads, with the ability to fork threads and switch agents mid-conversation. The system uses Ash Framework for domain modeling, GenStage for async message processing, and ReqLLM with a local llama-swap backend for LLM completions.

## Goals

- Unified conversation threads accessible from both web UI and Telegram
- Support multiple AI agents with configurable tools (read/create/edit/bash)
- Admin dashboard for agent and tool management
- Async message processing with lifecycle events via GenStage
- SQLite persistence via Ash Framework
- Thread forking capability

## User Stories

### US-001: Project Setup and Ash Domain Structure
**Description:** As a developer, I need the foundational project structure with Ash domains so I can build features on top.

**Acceptance Criteria:**
- [ ] Phoenix project created with LiveView
- [ ] Ash Framework configured with SQLite (AshSqlite)
- [ ] `Piano.Chat` domain with `Thread` and `Message` resources
- [ ] `Piano.Agents` domain with `Agent` resource
- [ ] Migrations generated and applied
- [ ] `mix compile` passes

---

### US-002: Thread Resource
**Description:** As a developer, I need a Thread resource to represent conversation sessions.

**Acceptance Criteria:**
- [ ] Thread has: `id` (UUID), `title` (string, optional), `status` (:active/:archived), `inserted_at`
- [ ] Thread has `has_many :messages` relationship
- [ ] Thread has `belongs_to :primary_agent` (optional)
- [ ] Actions: `:create`, `:read`, `:list`, `:archive`
- [ ] `mix compile` passes

---

### US-003: Message Resource
**Description:** As a developer, I need a Message resource to store chat messages.

**Acceptance Criteria:**
- [ ] Message has: `id` (UUID), `content` (text), `role` (:user/:agent), `source` (:web/:telegram), `inserted_at`
- [ ] Message has `belongs_to :thread` (required)
- [ ] Message has `belongs_to :agent` (optional, set for agent messages)
- [ ] Actions: `:create`, `:read`, `:list_by_thread`
- [ ] `mix compile` passes

---

### US-004: Agent Resource
**Description:** As a developer, I need an Agent resource to configure AI assistants.

**Acceptance Criteria:**
- [ ] Agent has: `id` (UUID), `name` (string), `description` (text), `model` (string), `system_prompt` (text)
- [ ] Agent has `enabled_tools` (array of strings, default: `[]`)
- [ ] Agent has `enabled_skills` (array of strings, default: `[]`)
- [ ] Actions: `:create`, `:read`, `:list`, `:update_config`
- [ ] Seed a default agent on first run
- [ ] `mix compile` passes

---

### US-005: Tool Registry
**Description:** As a developer, I need a tool registry to define and manage available tools.

**Acceptance Criteria:**
- [ ] `Piano.Agents.ToolRegistry` module created
- [ ] Tools defined: `read_file`, `create_file`, `edit_file`, `bash`
- [ ] Each tool has: name, description, parameters schema, callback function
- [ ] `get_tools(enabled_tool_names)` returns list of tool definitions
- [ ] `list_available/0` returns all tool names
- [ ] `mix compile` passes

---

### US-006: Skill Loader
**Description:** As a developer, I need to load skills from `.agents/skills` directory.

**Acceptance Criteria:**
- [ ] `Piano.Agents.SkillRegistry` module created
- [ ] Scans `.agents/skills/` for `.md` files on startup
- [ ] Each skill file becomes a prompt snippet keyed by filename
- [ ] `get_prompts(enabled_skill_names)` returns concatenated prompt text
- [ ] `list_available/0` returns all skill names
- [ ] `mix compile` passes

---

### US-007: GenStage Message Producer
**Description:** As a developer, I need a GenStage producer to receive incoming messages.

**Acceptance Criteria:**
- [ ] `Piano.Pipeline.MessageProducer` GenStage module
- [ ] `enqueue/1` function to add message events
- [ ] Buffers events until consumers request them
- [ ] Supervised under application
- [ ] `mix compile` passes

---

### US-008: GenStage Agent Consumer
**Description:** As a developer, I need a GenStage consumer to process messages and call the LLM.

**Acceptance Criteria:**
- [ ] `Piano.Pipeline.AgentConsumer` GenStage module
- [ ] Subscribes to MessageProducer
- [ ] Loads agent config, enabled tools, enabled skills
- [ ] Builds message history from thread
- [ ] Calls ReqLLM with llama-swap endpoint
- [ ] Creates agent Message in database with response
- [ ] Broadcasts lifecycle events: `:processing_started`, `:response_ready`
- [ ] `mix compile` passes

---

### US-009: Chat Gateway
**Description:** As a developer, I need a unified gateway to handle incoming messages from any channel.

**Acceptance Criteria:**
- [ ] `Piano.ChatGateway` module
- [ ] `handle_incoming(content, source, metadata)` function
- [ ] Resolves thread and agent from metadata
- [ ] Creates user Message via Ash
- [ ] Enqueues to MessageProducer
- [ ] Returns `{:ok, message}` or `{:error, reason}`
- [ ] `mix compile` passes

---

### US-010: PubSub Event Broadcasting
**Description:** As a developer, I need a PubSub system to broadcast pipeline events to UI.

**Acceptance Criteria:**
- [ ] `Piano.PubSub` configured in application
- [ ] Topics: `"thread:#{thread_id}"` for thread-specific events
- [ ] Events: `{:processing_started, message_id}`, `{:response_ready, message}`
- [ ] Helper `Piano.Events.broadcast/2` and `subscribe/1`
- [ ] `mix compile` passes

---

### US-011: Chat LiveView - Basic UI
**Description:** As a user, I want a web chat interface to send messages and see responses.

**Acceptance Criteria:**
- [ ] `PianoWeb.ChatLive` LiveView at `/chat`
- [ ] Shows list of messages in current thread
- [ ] Text input and send button
- [ ] Sends message via ChatGateway on submit
- [ ] Subscribes to thread PubSub topic
- [ ] Appends new messages on `:response_ready` event
- [ ] Shows "thinking..." indicator on `:processing_started`
- [ ] `mix compile` passes
- [ ] Verify in browser

---

### US-012: Thread Switching in Chat UI
**Description:** As a user, I want to switch between conversation threads.

**Acceptance Criteria:**
- [ ] Sidebar or dropdown showing all threads
- [ ] Clicking a thread loads its messages
- [ ] "New Thread" button creates a new thread
- [ ] URL updates to `/chat?thread=<id>`
- [ ] `mix compile` passes
- [ ] Verify in browser

---

### US-013: Thread Forking
**Description:** As a user, I want to fork a thread from a specific message to explore alternatives.

**Acceptance Criteria:**
- [ ] Fork button/icon on each message
- [ ] Clicking creates new thread with messages up to that point
- [ ] New thread has `forked_from_thread_id` and `forked_from_message_id` attributes
- [ ] User is switched to the new forked thread
- [ ] Ash action `Thread.fork/2` handles the logic
- [ ] `mix compile` passes
- [ ] Verify in browser

---

### US-014: Agent Selection in Chat
**Description:** As a user, I want to select which agent responds to my message.

**Acceptance Criteria:**
- [ ] Dropdown showing available agents above input
- [ ] Selected agent is passed to ChatGateway
- [ ] Agent name shown on agent messages
- [ ] Default to thread's primary agent if not selected
- [ ] `mix compile` passes
- [ ] Verify in browser

---

### US-015: Admin Dashboard - Agent List
**Description:** As an admin, I want to see all configured agents.

**Acceptance Criteria:**
- [ ] `PianoWeb.Admin.AgentListLive` at `/admin/agents`
- [ ] Lists all agents with name, model, enabled tools count
- [ ] Link to edit each agent
- [ ] Protected by startup token (query param or session)
- [ ] `mix compile` passes
- [ ] Verify in browser

---

### US-016: Admin Dashboard - Agent Configuration
**Description:** As an admin, I want to configure an agent's tools and skills.

**Acceptance Criteria:**
- [ ] `PianoWeb.Admin.AgentConfigLive` at `/admin/agents/:id`
- [ ] Shows agent name, description, model, system_prompt (editable)
- [ ] Lists all available tools with toggle switches
- [ ] Lists all available skills with toggle switches
- [ ] Toggles update agent via Ash `update_config` action
- [ ] Changes persist to database
- [ ] `mix compile` passes
- [ ] Verify in browser

---

### US-017: Admin Token Authentication
**Description:** As a developer, I need to secure admin routes with a startup token.

**Acceptance Criteria:**
- [ ] Random token generated on application start
- [ ] Token printed to console
- [ ] Admin routes require `?token=<value>` or session cookie
- [ ] Invalid/missing token returns 403
- [ ] `mix compile` passes

---

### US-018: Telegram Bot Setup
**Description:** As a developer, I need the Telegram bot to receive messages.

**Acceptance Criteria:**
- [ ] `Piano.Telegram.Bot` module using ExGram
- [ ] Bot token from config/env
- [ ] Handles `/start` command with welcome message
- [ ] Supervised under application
- [ ] `mix compile` passes

---

### US-019: Telegram Message Handling
**Description:** As a user, I want to chat with the AI via Telegram.

**Acceptance Criteria:**
- [ ] Text messages forwarded to `ChatGateway.handle_incoming/3`
- [ ] Source set to `:telegram`, metadata includes `chat_id`
- [ ] Agent response sent back via Telegram API (using Req)
- [ ] "typing" action sent while processing
- [ ] `mix compile` passes

---

### US-020: Telegram Thread Mapping
**Description:** As a developer, I need to map Telegram chats to threads.

**Acceptance Criteria:**
- [ ] `Piano.Telegram.SessionMapper` module
- [ ] Maps `chat_id` to active `thread_id`
- [ ] Creates new thread if none exists for chat
- [ ] `/newthread` command creates fresh thread
- [ ] `/thread <id>` switches to existing thread
- [ ] `mix compile` passes

---

### US-021: ReqLLM Integration
**Description:** As a developer, I need to configure ReqLLM for llama-swap backend.

**Acceptance Criteria:**
- [ ] ReqLLM configured with llama-swap base URL from config
- [ ] `Piano.LLM.complete/3` wrapper function
- [ ] Accepts messages, tools, model name
- [ ] Handles tool calls and returns final response
- [ ] Error handling for API failures
- [ ] `mix compile` passes

---

### US-022: Tool Execution - read_file
**Description:** As an agent, I can read file contents.

**Acceptance Criteria:**
- [ ] Tool accepts `path` parameter
- [ ] Returns file content or error message
- [ ] Path restricted to safe directories (configurable)
- [ ] `mix compile` passes

---

### US-023: Tool Execution - create_file
**Description:** As an agent, I can create new files.

**Acceptance Criteria:**
- [ ] Tool accepts `path` and `content` parameters
- [ ] Creates file at path with content
- [ ] Returns success/error message
- [ ] Path restricted to safe directories
- [ ] `mix compile` passes

---

### US-024: Tool Execution - edit_file
**Description:** As an agent, I can edit existing files.

**Acceptance Criteria:**
- [ ] Tool accepts `path`, `old_content`, `new_content` parameters
- [ ] Replaces old_content with new_content in file
- [ ] Returns success/error message
- [ ] Path restricted to safe directories
- [ ] `mix compile` passes

---

### US-025: Tool Execution - bash
**Description:** As an agent, I can execute shell commands.

**Acceptance Criteria:**
- [ ] Tool accepts `command` parameter
- [ ] Executes via `System.cmd/3` with timeout
- [ ] Returns stdout/stderr and exit code
- [ ] Configurable allowed commands or sandboxing
- [ ] `mix compile` passes

---

### US-026: End-to-End Test - Web Chat Flow
**Description:** As a developer, I need an E2E test for the web chat flow.

**Acceptance Criteria:**
- [ ] Test creates thread, sends message, receives agent response
- [ ] Uses mock LLM response
- [ ] Verifies message stored in database
- [ ] Verifies PubSub events broadcast
- [ ] `mix test` passes

---

### US-027: End-to-End Test - Telegram Flow
**Description:** As a developer, I need an E2E test for the Telegram flow.

**Acceptance Criteria:**
- [ ] Test simulates incoming Telegram message
- [ ] Uses mock LLM response
- [ ] Verifies response sent back (mocked Telegram API)
- [ ] Verifies message stored with source `:telegram`
- [ ] `mix test` passes

---

## Functional Requirements

- FR-1: All data persisted in SQLite via Ash Framework
- FR-2: Messages processed asynchronously via GenStage pipeline
- FR-3: Lifecycle events broadcast via Phoenix PubSub
- FR-4: Agents can only use tools that are enabled in their config
- FR-5: Skills loaded dynamically from `.agents/skills/` directory
- FR-6: Admin access requires startup token
- FR-7: Telegram and Web messages use the same processing pipeline
- FR-8: Thread forking copies all messages up to the fork point
- FR-9: LLM calls use ReqLLM with OpenAI-compatible llama-swap endpoint
- FR-10: Tool execution is sandboxed to configured safe paths/commands

## Non-Goals

- Multi-user authentication (single user only for now)
- Streaming responses (non-streaming initially)
- Docker sandboxing for code execution
- Multi-model support (llama-swap only initially)
- Message editing or deletion
- File attachments or images
- Voice messages

## Technical Considerations

- **Ash Framework:** Use for all CRUD operations, leverage actions and relationships
- **GenStage:** Single producer, single consumer initially; can scale to partitioned consumers per agent later
- **ExGram:** Use for Telegram bot with long polling mode
- **ReqLLM:** Configure for llama-swap's OpenAI-compatible API
- **Phoenix PubSub:** Use for real-time UI updates
- **SQLite:** Lightweight, no external DB setup needed

## Success Metrics

- User can send message via web and receive agent response within 30s
- User can send message via Telegram and receive response
- Admin can toggle tools on/off and changes take effect immediately
- Thread fork creates accurate copy of conversation history
- All tools (read/create/edit/bash) function correctly when enabled

## Open Questions

- Should tool execution have rate limiting?
- What's the maximum context length to send to llama-swap?
- Should we support multiple simultaneous llama-swap models?
- How to handle llama-swap being unavailable (queue messages? fail fast?)
