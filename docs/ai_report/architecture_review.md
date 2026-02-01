# Piano Architecture Review

## Executive Summary

Piano is a well-architected Elixir application that serves as an orchestration layer between external messaging platforms (Telegram) and OpenAI's Codex app-server. The codebase demonstrates solid software engineering practices with clean separation of concerns, protocol-based extensibility, and comprehensive event handling.

## System Overview

### High-Level Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Telegram      │────▶│     Piano        │────▶│  Codex App      │
│   Surface       │     │   Orchestrator   │     │  Server         │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                       │                        │
         │              ┌────────┴────────┐              │
         │              │                 │              │
         ▼              ▼                 ▼              ▼
┌─────────────────┐ ┌──────────┐   ┌───────────┐ ┌─────────────────┐
│  Core Domain    │ │ Pipeline │   │  Browser  │ │  MCP Tools      │
│  (Ash/SQLite)   │ │(Broadway)│   │  Agent    │ │  (Web Fetch)    │
└─────────────────┘ └──────────┘   └───────────┘ └─────────────────┘
```

### Key Components

#### 1. Surface Layer (`lib/piano/surface.ex`, `lib/piano/telegram/surface.ex`)
- **Protocol-based design**: `Piano.Surface` protocol defines lifecycle callbacks
- **Current implementation**: Telegram surface with rich message formatting
- **Surface Context**: Unified context passing for interaction/turn/thread data
- **Features**: Progress updates with emoji, tool call previews, transcript generation

#### 2. Core Domain (`lib/piano/core/`)
- **Ash Framework**: Resource-based domain modeling with SQLite persistence
- **Resources**:
  - `Surface`: External integration identifiers
  - `Agent`: Codex agent configuration (model, workspace, policies)
  - `Thread`: Conversation threads linked to Codex thread IDs
  - `Interaction`: Individual user interactions
  - `InteractionItem`: Granular items (messages, tool calls, file changes)

#### 3. Codex Integration (`lib/piano/codex/`)
- **Client**: GenServer wrapping `codex app-server` process via JSON-RPC over stdio
- **Events**: Comprehensive event parsing (30+ event types)
- **Persistence**: Event-to-database mapping with interaction tracking
- **Notifications**: Surface notification routing
- **Responses**: Structured RPC response handling

#### 4. Pipeline (`lib/piano/pipeline/`)
- **Broadway-based**: Partitioned event processing by thread_id
- **Producer**: In-memory queue for Codex events
- **Consumer**: Orchestrates persistence and notifications
- **Partitioning**: Ensures ordered processing per thread

#### 5. Tools (`lib/piano/tools/`)
- **Web Cleaner**: HTML fetching and content extraction via Req/Floki
- **Browser Agent**: Wallaby-based headless browser automation
- **MCP Integration**: Model Context Protocol tools for web fetch and browser actions

#### 6. Web Layer (`lib/piano_web/`)
- **Phoenix/LiveView**: Web interface with LiveDashboard
- **MCP Endpoint**: `/mcp` route for AI tool access
- **Admin**: Dashboard with telemetry and Ecto repos

## Architecture Strengths

### 1. Protocol-Based Extensibility
The `Piano.Surface` protocol with lifecycle callbacks (`on_turn_started`, `on_item_completed`, etc.) provides a clean contract for new surface implementations. The fallback implementation ensures graceful degradation.

### 2. Event-Driven Architecture
Comprehensive event handling with structured structs for:
- Turn lifecycle (started, completed, diff updated, plan updated)
- Item lifecycle (started, completed, deltas)
- Thread lifecycle (started, archived, token usage)
- Account/auth events
- Approval flows

### 3. Partitioned Processing
Broadway pipeline with partitioning by thread_id ensures:
- Ordered event processing per conversation
- Concurrent processing across different threads
- Backpressure handling via GenStage

### 4. Persistence Strategy
Smart event-to-database mapping:
- Events map to interactions and interaction_items
- Graceful handling of missing mappings
- Response extraction from agent messages

### 5. Context Management
The `Surface.Context` struct unifies access to:
- Interaction (may be nil for thread-level events)
- Turn/thread IDs
- Parsed events
- Raw parameters

### 6. Observability
Comprehensive logging with structured metadata:
- Interaction/thread/turn IDs
- Chat identifiers
- Event types
- Token usage statistics

## Areas for Improvement

### 1. User Management
**Current State**: No user entity exists. Surfaces are identified only by chat_id.
**Impact**: Cannot distinguish users in group chats or maintain user preferences.
**Recommendation**: Implement User resource and users_surfaces join table.

### 2. Permission System
**Current State**: No role-based access control.
**Impact**: Cannot restrict commands or features based on user roles.
**Recommendation**: Add role field to users (admin, user) and permission checks in handlers.

### 3. Memory Management
**Current State**: Only short-term context window (last 15 messages) for group chats.
**Impact**: No long-term memory or knowledge persistence across threads.
**Recommendation**: Implement vector store integration for semantic memory.

### 4. Multimodality
**Current State**: Text-only interaction with no image/audio support.
**Impact**: Cannot process screenshots, voice messages, or documents.
**Recommendation**: Add image processing via vision models, audio transcription.

### 5. Surface Ecosystem
**Current State**: Only Telegram surface implemented.
**Impact**: Limited to single platform.
**Recommendation**: Implement LiveView surface with feature parity for web interface.

### 6. Agent Skills
**Current State**: Basic MCP tools (web fetch, browser), no skill system.
**Impact**: Agent capabilities limited to built-in tools.
**Recommendation**: Implement skill loading system (markdown-based) for extensibility.

### 7. Local Tool Surfaces
**Current State**: No support for local device integration.
**Impact**: Cannot control local hardware (cameras, IoT devices).
**Recommendation**: Design surface protocol extension for local tool providers.

## Code Quality Assessment

### Strengths
- **Type Safety**: Comprehensive type specs throughout
- **Error Handling**: Proper use of `{:ok, _}` / `{:error, _}` tuples
- **Documentation**: Excellent module and function documentation
- **Testing**: Test coverage exists for core components
- **Formatting**: Consistent code style (follows Elixir conventions)

### Areas for Attention
- **Complex Functions**: Some functions in `Codex.Persistence` and `Telegram.Surface` exceed 20 lines
- **Nested Conditionals**: Approval decision logic could be extracted
- **Hardcoded Values**: Some magic numbers (timeouts, limits) not configurable
- **Module Size**: `Codex.Events` is very large (896 lines) - could be split

## Data Model Review

### Schema Overview
```sql
surfaces          (id, app, identifier, config)
agents_v2         (id, name, model, workspace_path, sandbox_policy, auto_approve_policy, is_default)
threads_v2        (id, codex_thread_id, reply_to, status, agent_id)
interactions      (id, codex_turn_id, original_message, reply_to, status, response, thread_id)
interaction_items (id, codex_item_id, type, payload, status, interaction_id)
```

### Strengths
- Clean relational structure
- UUID primary keys
- Proper foreign key constraints
- Timestamps on all tables

### Gaps
- No users table
- No permissions/roles
- No memory/knowledge storage
- No skill definitions storage
- Limited audit trail

## Performance Considerations

### Current Optimizations
- Broadway partitioning prevents thread contention
- SQLite with proper indexing
- Context window size limits (configurable, default 200)
- Efficient queue operations via `:queue` module

### Potential Bottlenecks
- Database queries in notification path (synchronous)
- Browser agent single-session limitation
- No caching layer for frequently accessed data
- All event processing is single-threaded per partition

## Security Architecture

### Current Measures
- Admin token for dashboard access (randomly generated if not set)
- Telegram bot token from environment
- No secrets in code

### Gaps (See security_report.md for details)
- No user authentication/authorization
- No rate limiting
- No input validation/sanitization beyond HTML escaping
- No audit logging
- Admin token may be predictable if configured

## Scalability Assessment

### Current Scale
- Single-node deployment
- SQLite database (file-based)
- In-memory event queue

### Scaling Limitations
- SQLite limits concurrent writes
- No horizontal scaling strategy
- State stored in single GenServer processes
- No load balancing for multiple instances

### Scaling Path
1. Migrate to PostgreSQL for multi-node support
2. Add Redis for distributed state
3. Implement stateless surface handlers
4. Add clustering support via `libcluster`

## Technology Stack Evaluation

### Appropriate Choices
- **Elixir/OTP**: Excellent for concurrent, event-driven systems
- **Phoenix**: Mature web framework with LiveView
- **Ash Framework**: Strong resource modeling with policy support
- **Broadway**: Battle-tested message processing
- **SQLite**: Suitable for single-node, embedded deployments

### Consider Alternatives For
- **SQLite -> PostgreSQL**: If multi-node scaling needed
- **In-memory queue -> RabbitMQ/Kafka**: If event volume grows significantly
- **Agent -> ETS/cache**: For frequently accessed configuration

## Conclusion

Piano demonstrates solid architectural foundations with clean separation of concerns, protocol-based extensibility, and comprehensive event handling. The codebase is well-structured for an MVP/single-tenant deployment but will require enhancements for multi-tenancy, scaling, and advanced features like memory management and multimodality.

**Architectural Maturity**: 8/10 - Production-ready for single-tenant use
**Extensibility**: 9/10 - Protocol-based design enables easy surface/tool additions
**Scalability**: 5/10 - Limited to single-node due to SQLite and in-memory state
**Maintainability**: 8/10 - Clean code, good documentation, comprehensive types

## Recommendations Priority Matrix

| Priority | Area | Effort | Impact |
|----------|------|--------|--------|
| P0 | User Management | Medium | High |
| P0 | Security Hardening | Low | High |
| P1 | LiveView Surface | Medium | High |
| P1 | Memory System | High | High |
| P2 | Multimodality | High | Medium |
| P2 | Skills Framework | Medium | Medium |
| P3 | PostgreSQL Migration | High | Medium |
| P3 | Local Tools Surface | High | Low |
