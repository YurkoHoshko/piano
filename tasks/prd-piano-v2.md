# PRD: Piano v2 - Multi-Agent Orchestration System

## Introduction

Piano v2 wraps Codex app-server to enable multi-surface AI interactions. Surfaces (Telegram, LiveView) produce Interactions that flow through a simple pipeline to Codex, with events streamed back to the originating Surface.

## Goals

- Clean domain model: Surface, Thread, Interaction, Agent
- Codex app-server integration with event streaming
- Surface protocol for Telegram (MVP)
- **MVP: End-to-end Telegram flow from message to response**

## Flow

```
Surface receives message
    → creates Interaction
    → calls InteractionPipeline.enqueue(interaction)
        → finds/creates Thread for surface
        → assigns thread_id to Interaction  
        → calls Codex.start_turn(interaction)
            → streams turn/*, item/* events
            → calls Surface.handle_event(surface, interaction, event) for each
            → updates InteractionItem / Interaction on completion
```

## Model Mapping

| Piano | Codex |
|-------|-------|
| Thread | Thread (stores codex_thread_id) |
| Interaction | Turn (stores codex_turn_id) |
| Agent | cwd + AGENTS.md |

## User Stories

### Phase 1: Core Schemas

#### US-001: Surface Schema
**Description:** As a developer, I need a Surface schema.

**Acceptance Criteria:**
- [ ] `Piano.Core.Surface` Ash resource
- [ ] Attributes: `id`, `app` (:telegram/:liveview), `identifier`, `config` (map)
- [ ] Actions: `:create`, `:read`, `:get_by_app_and_identifier`
- [ ] `mix compile` passes
- [ ] Unit tests pass

---

#### US-002: Agent Schema
**Description:** As a developer, I need an Agent schema.

**Acceptance Criteria:**
- [ ] `Piano.Core.Agent` Ash resource
- [ ] Attributes: `id`, `name`, `model`, `workspace_path` (folder with AGENTS.md), `sandbox_policy`, `auto_approve_policy`
- [ ] Actions: `:create`, `:read`, `:update`, `:list`, `:get_default`
- [ ] `mix compile` passes
- [ ] Unit tests pass

---

#### US-003: Thread Schema
**Description:** As a developer, I need a Thread schema.

**Acceptance Criteria:**
- [ ] `Piano.Core.Thread` Ash resource
- [ ] Attributes: `id`, `codex_thread_id`, `status` (:active/:archived), timestamps
- [ ] Relationships: `has_many :interactions`, `belongs_to :agent`, `belongs_to :surface`
- [ ] Actions: `:create`, `:read`, `:archive`, `:find_recent_for_surface`
- [ ] `mix compile` passes
- [ ] Unit tests pass

---

#### US-004: Interaction Schema
**Description:** As a developer, I need an Interaction schema.

**Acceptance Criteria:**
- [ ] `Piano.Core.Interaction` Ash resource
- [ ] Attributes: `id`, `codex_turn_id`, `original_message`, `status` (:pending/:in_progress/:complete/:interrupted/:failed), `response`
- [ ] Relationships: `belongs_to :thread`, `belongs_to :surface`, `has_many :items`
- [ ] Actions: `:create`, `:start`, `:complete`, `:fail`, `:interrupt`
- [ ] `mix compile` passes
- [ ] Unit tests pass

---

#### US-005: InteractionItem Schema
**Description:** As a developer, I need an InteractionItem schema.

**Acceptance Criteria:**
- [ ] `Piano.Core.InteractionItem` Ash resource
- [ ] Attributes: `id`, `codex_item_id`, `type`, `payload` (map), `status`
- [ ] Relationships: `belongs_to :interaction`
- [ ] Actions: `:create`, `:complete`, `:list_by_interaction`
- [ ] `mix compile` passes
- [ ] Unit tests pass

---

### Phase 2: Codex Integration

#### US-006: Codex Client
**Description:** As a developer, I need a client for Codex app-server.

**Acceptance Criteria:**
- [ ] `Piano.Codex.Client` GenServer wrapping `codex app-server` process
- [ ] JSON-RPC 2.0 over stdio (JSONL)
- [ ] `initialize/1` handshake on start
- [ ] Supervised, restarts on crash
- [ ] `mix compile` passes
- [ ] Unit tests pass

---

#### US-007: Codex.start_turn/1
**Description:** As a developer, I need to start a Codex turn for an interaction.

**Acceptance Criteria:**
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

---

### Phase 3: Surface Protocol

#### US-008: Surface Behaviour
**Description:** As a developer, I need a Surface behaviour.

**Acceptance Criteria:**
- [ ] `Piano.Surface` behaviour module
- [ ] `@callback handle_event(surface, interaction, event) :: {:ok, term()} | {:ok, :noop}`
- [ ] Events: `:turn_started`, `:item_started`, `:item_completed`, `:agent_message_delta`, `:turn_completed`, `:approval_required`
- [ ] `@callback send_message(surface, message) :: :ok`
- [ ] `@callback send_typing(surface) :: :ok`
- [ ] `mix compile` passes

---

#### US-009: Telegram Surface
**Description:** As a developer, I need Telegram Surface implementation.

**Acceptance Criteria:**
- [ ] `Piano.Surface.Telegram` implements `Piano.Surface`
- [ ] `handle_event` for `:turn_started` → sends typing indicator
- [ ] `handle_event` for `:agent_message_delta` → accumulates text (or streams via edit)
- [ ] `handle_event` for `:turn_completed` → sends final message
- [ ] `handle_event` for `:approval_required` → sends inline keyboard, waits for callback, returns decision
- [ ] `send_message/2` sends via Telegram API
- [ ] `mix compile` passes
- [ ] Unit tests pass

---

### Phase 4: Pipeline

#### US-010: InteractionPipeline.enqueue/1
**Description:** As a developer, I need a pipeline entry point.

**Acceptance Criteria:**
- [ ] `Piano.InteractionPipeline.enqueue(interaction)` function
- [ ] Finds active thread for surface (recent activity) or creates new one
- [ ] Assigns `thread_id` to interaction
- [ ] Calls `Codex.start_turn(interaction)`
- [ ] Returns `{:ok, interaction}` or `{:error, reason}`
- [ ] `mix compile` passes
- [ ] Unit tests pass

---

### Phase 5: Test Harness

#### US-011: Mock LLM API Server
**Description:** As a developer, I need a mock API for testing Codex.

**Acceptance Criteria:**
- [ ] `Piano.TestHarness.MockLLMServer` Plug-based server
- [ ] OpenAI chat completions endpoint
- [ ] Configurable response sequences
- [ ] Supports tool calls
- [ ] `mix compile` passes
- [ ] Unit tests pass

---

#### US-012: Codex Integration Test
**Description:** As a developer, I need E2E tests for Codex flow.

**Acceptance Criteria:**
- [ ] Test: message → Codex → mock API → response → interaction completed
- [ ] Test: approval flow with mock tool call
- [ ] Test: turn interruption
- [ ] Uses real Codex app-server with mock API backend
- [ ] `mix test` passes

---

### Phase 6: Telegram Bot

#### US-013: Telegram Bot
**Description:** As a developer, I need the Telegram bot.

**Acceptance Criteria:**
- [ ] `Piano.Telegram.Bot` using ExGram
- [ ] On text message: create Surface, create Interaction, call `InteractionPipeline.enqueue`
- [ ] Handles `/start`, `/newthread` commands
- [ ] `mix compile` passes

---

#### US-014: End-to-End Telegram Test
**Description:** As a developer, I need E2E test for Telegram flow.

**Acceptance Criteria:**
- [ ] Test: Telegram message → full pipeline → response sent
- [ ] Test: Approval via inline keyboard
- [ ] Uses mock LLM API + mocked Telegram API
- [ ] `mix test` passes

---

## Functional Requirements

- FR-1: Schemas persist via Ash/SQLite
- FR-2: Thread stores `codex_thread_id`, Interaction stores `codex_turn_id`
- FR-3: Agent config passed to Codex via `cwd`, `model`, `sandboxPolicy`
- FR-4: Events streamed to Surface via `handle_event` callback
- FR-5: Approvals routed through Surface, response sent back to Codex

## Non-Goals (MVP)

- LiveView Surface
- Memory/Archivist
- Scheduled tasks
- Broadway partitioning (Codex handles it)

## Technical Considerations

- **Codex App-Server:** JSON-RPC 2.0 over stdio
- **Agent = cwd:** Workspace folder with AGENTS.md
- **Event streaming:** `Codex.start_turn` streams events to `Surface.handle_event`
- **Test Harness:** Mock OpenAI API for predictable testing

## Open Questions

- Thread timeout for "recent" detection?
- One Codex process per agent or shared?
