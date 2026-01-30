# Codex Config (Basics + Advanced + Reference)

Sources:
- https://developers.openai.com/codex/config-basic
- https://developers.openai.com/codex/config-advanced
- https://developers.openai.com/codex/config-reference
Retrieved: 2026-01-30

This is a high-fidelity paraphrase for local reference. It avoids long verbatim excerpts; consult the sources above for exact wording.

---

## Config basics

### Where config lives
- User defaults: `~/.codex/config.toml`.
- Project overrides: `.codex/config.toml` inside a repo (loaded only when the project is trusted).
- CLI and IDE extension share the same configuration layers.

### Precedence order (highest to lowest)
1) CLI flags and `--config` overrides.
2) Profile values (`--profile <name>`).
3) Project `.codex/config.toml` files from repo root to current working directory (closest wins; trusted projects only).
4) User config (`~/.codex/config.toml`).
5) System config (if present): `/etc/codex/config.toml` on Unix.
6) Built-in defaults.

If a project is untrusted, Codex skips project `.codex/` config layers and falls back to user/system/defaults.

### Common settings
- Default model: `model = "gpt-5.2"` (example).
- Approval prompts: `approval_policy = "on-request"`.
- Sandbox level: `sandbox_mode = "workspace-write"`.
- Web search mode:
  - `"cached"` (default) uses cached results.
  - `"live"` fetches fresh results (same as `--search`).
  - `"disabled"` turns off web search.
- Reasoning effort: `model_reasoning_effort = "high"`.
- Command environment allowlist:
  ```toml
  [shell_environment_policy]
  include_only = ["PATH", "HOME"]
  ```

### Feature flags
Use `[features]` in `config.toml` or `codex --enable feature_name` to toggle optional/experimental features. Omit keys to keep defaults.

---

## Advanced config

### Profiles (experimental)
- Define profiles under `[profiles.<name>]` in `config.toml`.
- Activate with `codex --profile <name>`; make a profile default with `profile = "<name>"`.
- Profiles are experimental and not supported in the IDE extension.

### One-off CLI overrides
- Prefer dedicated flags like `--model` when available.
- Use `-c` / `--config` for arbitrary keys; values are parsed as TOML.
- Dot notation is supported for nested keys (e.g., `mcp_servers.context7.enabled=false`).

### Config and state locations
- Codex state lives in `CODEX_HOME` (defaults to `~/.codex`).
- Typical files: `config.toml`, `auth.json` (if using file storage), `history.jsonl`, plus logs/caches.

### Project config files
- Codex loads all `.codex/config.toml` files from project root to your cwd.
- For security, project config is only loaded when the project is trusted.
- Relative paths inside project config resolve relative to that `.codex/` directory.

### Project root detection
- By default, a directory with `.git` is treated as a project root.
- Customize with `project_root_markers` in `config.toml`, or set it to `[]` to stop walking upward.

### Custom model providers
- Use `model_provider` to select a provider defined in `[model_providers.<id>]`.
- Providers can set `base_url`, `env_key`, and optional request headers.

### OSS mode (local providers)
- `codex --oss` runs against a local provider (e.g., Ollama or LM Studio).
- `oss_provider` sets the default provider when `--oss` is used without one.

### Model reasoning & verbosity
- Controls include `model_reasoning_summary`, `model_verbosity`, `model_supports_reasoning_summaries`, and `model_context_window`.
- `model_verbosity` applies to Responses API providers; Chat Completions providers ignore it.

### Observability (OpenTelemetry)
- Enable OTel export via `[otel]` with an exporter choice like `otlp-http` or `otlp-grpc`.
- `log_user_prompt` is opt-in to avoid capturing prompts by default.

### Hide or show reasoning output
- `hide_agent_reasoning = true` suppresses reasoning events.
- `show_raw_agent_reasoning = true` surfaces raw reasoning when the provider emits it.

### Notifications
- `notify` runs an external program (good for webhooks/desktop/CI).
- `tui.notifications` is built into the TUI and can filter event types.
- `tui.notification_method` controls the terminal notification mechanism (`auto`, `osc9`, or `bel`).

---

## Config reference (selected keys)

This section summarizes notable keys and their intent. For the full list, consult the official reference.

### Top-level behavior
- `approval_policy`: `untrusted | on-failure | on-request | never` (when to pause for command approval).
- `sandbox_mode`: `read-only | workspace-write | danger-full-access` (filesystem/network access policy).
- `review_model`: optional model override used by `/review`.
- `web_search`: `disabled | cached | live`.
- `hide_agent_reasoning` / `show_raw_agent_reasoning`: control reasoning visibility.

### Sandbox (workspace-write)
- `sandbox_workspace_write.writable_roots`: additional writable roots.
- `sandbox_workspace_write.network_access`: allow outbound network in workspace-write.
- `sandbox_workspace_write.exclude_slash_tmp` / `exclude_tmpdir_env_var`: exclude `/tmp` or `$TMPDIR` from writable roots.

### Shell environment policy
- `shell_environment_policy.exclude`: glob patterns removed after defaults.
- `shell_environment_policy.set`: explicit env overrides applied to every subprocess.
- `shell_environment_policy.experimental_use_profile`: optional profile-based behavior.

### Model providers
- `model_provider`: provider id (defaults to `openai`).
- `model_providers.<id>.base_url`: API base URL.
- `model_providers.<id>.env_key`: API key environment variable.
- `model_providers.<id>.env_http_headers`: header values from env vars.
- `model_providers.<id>.http_headers`: static headers.
- `model_providers.<id>.query_params`: extra query parameters.
- `model_providers.<id>.request_max_retries`: retry count (default noted in docs).
- `model_providers.<id>.name`: display name.
- `model_providers.<id>.experimental_bearer_token`: discouraged direct token.

### Model reasoning controls
- `model_reasoning_effort`: `minimal | low | medium | high | xhigh`.
- `model_reasoning_summary`: `auto | concise | detailed | none`.
- `model_supports_reasoning_summaries`: force support when needed.

### MCP servers
- `mcp_servers.<id>.command`, `.args`, `.cwd`: stdio server launch config.
- `mcp_servers.<id>.url`: HTTP endpoint for streamable MCP servers.
- `mcp_servers.<id>.http_headers` / `.env_http_headers`: request headers.
- `mcp_servers.<id>.env_vars`: extra env vars to pass through.
- `mcp_servers.<id>.startup_timeout_ms` / `.startup_timeout_sec`: startup timeouts.
- `mcp_servers.<id>.tool_timeout_sec`: per-tool timeout.

### OTEL
- `otel.exporter`: `none | otlp-http | otlp-grpc`.
- `otel.exporter.<id>.endpoint`, `.headers`, `.protocol`.
- TLS paths for exporters and trace exporters (CA, client cert, private key).
- `otel.log_user_prompt`: enable user prompt logging.

### Profiles
- `profile`: default profile name (equivalent to `--profile`).
- `profiles.<name>.*`: any supported keys scoped to a profile.
- `profiles.<name>.web_search`: profile-scoped web search override.

### Project docs
- `project_doc_fallback_filenames`: additional doc names when `AGENTS.md` is missing.
- `project_doc_max_bytes`: size cap when reading `AGENTS.md`.
- `project_root_markers`: override project root detection.

### Skills
- `skills.config`: per-skill enablement list.
- `skills.config.<index>.path`: path to a skill folder.
- `skills.config.<index>.enabled`: boolean toggle.

### Tools, feedback, and UI
- `tool_output_token_limit`: max stored tokens per tool output.
- `feedback.enabled`: enable `/feedback` submission (default true).
- `file_opener`: URI scheme for opening citations (`vscode`, `cursor`, etc.).
- `tui`: table of TUI options, including notifications and animations.

### requirements.toml (admin-enforced)
- `requirements.toml` constrains security-sensitive settings users cannot override.
- Keys include `allowed_approval_policies`, `allowed_sandbox_modes`, and an MCP server allowlist with identity matching.
