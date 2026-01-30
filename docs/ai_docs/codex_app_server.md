# Codex App Server (Codex Docs Snapshot)

Source: https://developers.openai.com/codex/app-server
Retrieved: 2026-01-30

This is a high-fidelity paraphrase of the official Codex App Server documentation for local reference. It avoids long verbatim excerpts; for exact wording, consult the source.

## Overview
- The app-server protocol is the interface Codex uses for rich, first‑party style clients (e.g., IDE integrations).
- It is meant for deep product integration: authentication, conversation history, approval flows, and streaming agent events.
- The app-server implementation is open source in the Codex repo; see the Open Source page for the full component list.
- For automation or CI, the Codex SDK is the recommended path instead of app-server.

## Protocol
- The server streams JSON Lines over stdio (stdin/stdout), enabling bidirectional communication.
- The protocol is JSON‑RPC 2.0, but it intentionally omits the `"jsonrpc":"2.0"` field.

## Message schema
- **Request:** `method`, `params`, `id`
- **Response:** `id` and either `result` or `error`
- **Notification:** `method`, `params` (no `id`)

Example request:
```json
{ "method": "thread/start", "id": 10, "params": { "model": "gpt-5.1-codex" } }
```

Example response:
```json
{ "id": 10, "result": { "thread": { "id": "thr_123" } } }
```

Example notification:
```json
{ "method": "turn/started", "params": { "turn": { "id": "turn_456" } } }
```

Schema generation from the CLI (version‑specific to your installed Codex build):
```
codex app-server generate-ts --out ./schemas
codex app-server generate-json-schema --out ./schemas
```

## Getting started
1) Launch the server with `codex app-server`; it reads JSONL from stdin and writes only protocol messages to stdout.
2) Connect a client over stdio; send `initialize` then emit `initialized`.
3) Start a thread and a turn; keep reading streamed notifications.

## Core primitives
- **Thread:** Conversation container; threads hold turns.
- **Turn:** A single user request plus the agent’s work; turns stream incremental updates.
- **Item:** Atomic unit of input/output (messages, tool calls, command runs, file changes, etc.).

## Lifecycle overview
- **Initialize once:** Send `initialize` with client metadata, then emit `initialized`. Requests before this fail.
- **Create or resume a thread:** `thread/start`, `thread/resume`, or `thread/fork`.
- **Begin a turn:** `turn/start` with the target `threadId` and input items.
- **Stream events:** Read `item/started`, `item/completed`, deltas, and tool progress on stdout.
- **Finish:** Server emits `turn/completed` after completion or `turn/interrupt`.

## Initialization details
- `initialize` must happen exactly once per server process. Repeating it yields an “already initialized” error.
- Provide `clientInfo` (name/title/version). The `name` is used in compliance logs/allow‑lists for enterprise integrations.

Example:
```json
{
  "method": "initialize",
  "id": 0,
  "params": {
    "clientInfo": { "name": "my_client", "title": "My Client", "version": "0.1.0" }
  }
}
```

## API overview (high level)
Threads:
- `thread/start` (creates a new thread and emits `thread/started`)
- `thread/resume` (re‑opens a stored thread)
- `thread/fork` (branches history into a new thread)
- `thread/read` (read without subscribing; optional `includeTurns`)
- `thread/list` (cursor pagination; filter by provider, source kind, archived, etc.)
- `thread/loaded/list` (threads currently resident in memory)
- `thread/archive`, `thread/unarchive`
- `thread/rollback` (drop last N turns from in‑memory context)

Turns & review:
- `turn/start`, `turn/interrupt`
- `review/start` (Codex reviewer, emits review mode items)

Environment & tools:
- `command/exec` (run a single command under the sandbox)
- `model/list`, `collaborationMode/list`
- `tool/requestUserInput` (experimental)

Skills & MCP:
- `skills/list`, `skills/config/write`
- `mcpServer/oauth/login`, `mcpServerStatus/list`, `config/mcpServer/reload`

Config & feedback:
- `config/read`, `config/value/write`, `config/batchWrite`
- `configRequirements/read`
- `feedback/upload`

Auth/account:
- `account/read`, `account/login/start`, `account/login/cancel`, `account/logout`
- Notifications: `account/login/completed`, `account/updated`, `account/rateLimits/updated`
- `account/rateLimits/read`

## Threads (details)
Example start:
```json
{ "method": "thread/start", "id": 10, "params": {
  "model": "gpt-5.1-codex",
  "cwd": "/Users/me/project",
  "approvalPolicy": "never",
  "sandbox": "workspaceWrite"
} }
```

Notes:
- `thread/read` does not load the thread into memory and does not emit `thread/started`.
- `thread/list` supports cursor pagination; `sourceKinds` includes values like `cli`, `vscode`, `appServer`, `subAgent*`, and `unknown`.
- `thread/loaded/list` returns currently loaded thread IDs.
- `thread/archive` moves a thread’s JSONL log into the archive directory; `thread/unarchive` restores it.

## Turns (details)
Input items can be:
```json
{ "type": "text", "text": "Explain this diff" }
{ "type": "image", "url": "https://.../design.png" }
{ "type": "localImage", "path": "/tmp/screenshot.png" }
```

Per‑turn overrides:
- `model`, `effort`, `summary`, `cwd`, and `sandboxPolicy` can be overridden.
- `outputSchema` applies only to the current turn.

Example turn start:
```json
{ "method": "turn/start", "id": 30, "params": {
  "threadId": "thr_123",
  "input": [ { "type": "text", "text": "Run tests" } ],
  "cwd": "/Users/me/project",
  "approvalPolicy": "unlessTrusted",
  "sandboxPolicy": {
    "type": "workspaceWrite",
    "writableRoots": ["/Users/me/project"],
    "networkAccess": true
  },
  "model": "gpt-5.1-codex",
  "effort": "medium",
  "summary": "concise",
  "outputSchema": { "type": "object" }
} }
```

Interrupt:
```json
{ "method": "turn/interrupt", "id": 31, "params": { "threadId": "thr_123", "turnId": "turn_456" } }
```

## Review mode
- `review/start` runs the reviewer for a thread and streams review items.
- Targets include `uncommittedChanges`, `baseBranch`, `commit`, and `custom`.
- `delivery: "inline"` uses the current thread; `delivery: "detached"` forks a new review thread.

Review notification shape (example):
```json
{ "method": "item/started", "params": { "item": { "type": "enteredReviewMode", "id": "turn_900", "review": "current changes" } } }
```

## Command execution
`command/exec` runs a single command under the sandbox without creating a thread.
```json
{ "method": "command/exec", "id": 50, "params": {
  "command": ["ls", "-la"],
  "cwd": "/Users/me/project",
  "sandboxPolicy": { "type": "workspaceWrite" },
  "timeoutMs": 10000
} }
```

Notes:
- Empty `command` arrays are rejected.
- `sandboxPolicy` uses the same shape as `turn/start`.
- `timeoutMs` falls back to the server default when omitted.
- `externalSandbox` can be used when you already isolate the server process.

## Events
Common item types include:
- `userMessage`, `agentMessage`, `reasoning`
- `commandExecution`, `fileChange`
- `mcpToolCall`, `collabToolCall`
- `webSearch`, `imageView`
- `enteredReviewMode`, `exitedReviewMode`, `compacted`

Item lifecycle:
- `item/started` emits the full item at start (the item’s `id` matches later deltas).
- `item/completed` emits the final item; treat it as authoritative state.

Item deltas include:
- `item/agentMessage/delta`
- `item/reasoning/summaryTextDelta`, `item/reasoning/summaryPartAdded`, `item/reasoning/textDelta`
- `item/commandExecution/outputDelta`
- `item/fileChange/outputDelta`

Turn lifecycle:
- `turn/started`, `turn/completed`
- `turn/diff/updated` streams the aggregated unified diff across file changes.

## Errors
- On failure, a turn ends with `status: "failed"` plus `{ error: { message, codexErrorInfo?, additionalDetails? } }`.
- `codexErrorInfo` values include `ContextWindowExceeded`, `UsageLimitExceeded`, `HttpConnectionFailed`, `ResponseStreamConnectionFailed`, `ResponseStreamDisconnected`, `ResponseTooManyFailedAttempts`, `BadRequest`, `Unauthorized`, `SandboxError`, `InternalServerError`, `Other`.
- If available, upstream HTTP status is forwarded as `codexErrorInfo.httpStatusCode`.

## Approvals
Depending on user settings, command execution and file changes can require approval via server‑initiated requests. Clients respond with `{ "decision": "accept" | "decline" }`, and for command execution may include `acceptSettings`.

### Command execution approvals (order)
1) `item/started` with a `commandExecution` item in progress.
2) `item/commandExecution/requestApproval` with `itemId`, `threadId`, `turnId`, optional `reason`/`risk`, plus a parsed command for display.
3) Client replies with accept or decline.
4) `item/completed` with final `status` (`completed`, `failed`, or `declined`).

### File change approvals (order)
1) `item/started` with a `fileChange` item in progress.
2) `item/fileChange/requestApproval` with `itemId`, `threadId`, `turnId`, optional `reason`.
3) Client replies with accept or decline.
4) `item/completed` with final `status`.

## Skills
- Invoke a skill by including `$<skill-name>` in user text.
- Recommended: add a `skill` input item so the server injects the full instructions (reduces latency vs. name resolution).

Example invocation:
```json
{ "method": "turn/start", "id": 101, "params": {
  "threadId": "thread-1",
  "input": [
    { "type": "text", "text": "$skill-creator Add a new skill for triaging flaky CI." },
    { "type": "skill", "name": "skill-creator", "path": "/Users/me/.codex/skills/skill-creator/SKILL.md" }
  ]
} }
```

`skills/list` (optionally scoped by `cwds` and `forceReload`):
```json
{ "method": "skills/list", "id": 25, "params": { "cwds": ["/Users/me/project"], "forceReload": false } }
```

Enable/disable a skill by path:
```json
{ "method": "skills/config/write", "id": 26, "params": { "path": "/Users/me/.codex/skills/skill-creator/SKILL.md", "enabled": false } }
```

## Auth endpoints
Auth/account APIs include request/response methods plus server notifications (no `id`). They cover auth state, login flows, logout, and ChatGPT rate limits.

### Auth API overview
- `account/read`
- `account/login/start`
- `account/login/completed` (notify)
- `account/login/cancel`
- `account/logout`
- `account/updated` (notify)
- `account/rateLimits/read`
- `account/rateLimits/updated` (notify)
- `mcpServer/oauthLogin/completed` (notify)

### 1) Check auth state
Request:
```json
{ "method": "account/read", "id": 1, "params": { "refreshToken": false } }
```

Responses can indicate no account, API key auth, or ChatGPT auth. `requiresOpenaiAuth` reflects whether OpenAI credentials are required for the active provider. `refreshToken` forces a token refresh.

### 2) Log in with an API key
```json
{ "method": "account/login/start", "id": 2, "params": { "type": "apiKey", "apiKey": "sk-..." } }
```
Expect a result with `{ "type": "apiKey" }`, followed by notifications `account/login/completed` and `account/updated`.

### 3) Log in with ChatGPT (browser flow)
Start:
```json
{ "method": "account/login/start", "id": 3, "params": { "type": "chatgpt" } }
```
The result includes `loginId` and `authUrl`. Open `authUrl` in a browser; the app-server hosts the local callback. Then wait for `account/login/completed` and `account/updated` notifications.

### 4) Cancel a ChatGPT login
```json
{ "method": "account/login/cancel", "id": 4, "params": { "loginId": "<uuid>" } }
```

### 5) Logout
```json
{ "method": "account/logout", "id": 5 }
```

### 6) Rate limits (ChatGPT)
```json
{ "method": "account/rateLimits/read", "id": 6 }
```
Fields include `usedPercent`, `windowDurationMins`, and `resetsAt` (Unix timestamp).
