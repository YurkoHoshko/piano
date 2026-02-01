# Security Improvement Recommendations

## Current Security Posture

### Existing Measures
- Admin token randomly generated if not configured
- Telegram bot token from environment variable
- No secrets committed to code
- HTML escaping in Telegram messages

### Security Gaps Identified

## Critical (P0)

### 1. Admin Token Security

**Current Issue:**
```elixir
# lib/piano/application.ex:90-97
configured = System.get_env("PIANO_ADMIN_TOKEN") || Application.get_env(:piano, :admin_token)

token =
  if is_binary(configured) and configured != "" and configured != "piano_admin" do
    configured
  else
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
```

**Risk:** Default token "piano_admin" is predictable. Random generation happens after startup check.

**Recommendations:**
```elixir
# 1. Remove default token entirely
# 2. Require explicit token configuration in production
# 3. Add token entropy requirements (min 32 bytes)
# 4. Implement token rotation support

defp setup_admin_token do
  token = System.get_env("PIANO_ADMIN_TOKEN")
  
  if is_nil(token) or token == "" do
    if Piano.Env.prod?() do
      raise "PIANO_ADMIN_TOKEN must be set in production"
    else
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      Logger.warning("Generated ephemeral admin token: #{token}")
    end
  end
  
  # Validate minimum entropy
  if byte_size(Base.url_decode64!(token)) < 32 do
    Logger.warning("Admin token has low entropy, consider using 32+ bytes")
  end
  
  Application.put_env(:piano, :admin_token, token)
end
```

### 2. Input Validation & Sanitization

**Current Issues:**
- No validation on `original_message` length
- No rate limiting on interactions
- URL validation only checks starts_with("localhost")

**Recommendations:**

```elixir
# lib/piano/core/interaction.ex - Add validation
attributes do
  attribute :original_message, :string do
    allow_nil? false
    constraints min_length: 1, max_length: 100_000  # Prevent DoS
  end
end

# Add changeset validation
changes do
  change {MyApp.Validations, :validate_message_content}
end
```

### 3. Rate Limiting

**Implementation:**

```elixir
# lib/piano_web/plugs/rate_limiter.ex
defmodule PianoWeb.RateLimiter do
  @moduledoc """
  Rate limiting for Telegram webhooks and MCP endpoints.
  Uses ETS for in-memory counters with TTL.
  """
  
  def init(opts), do: opts
  
  def call(conn, opts) do
    key = get_client_key(conn)
    max_requests = Keyword.get(opts, :max_requests, 100)
    window_ms = Keyword.get(opts, :window_ms, 60_000)
    
    case check_rate(key, max_requests, window_ms) do
      {:allow, _count} -> conn
      {:deny, _count} -> 
        conn
        |> send_resp(429, "Too many requests")
        |> halt()
    end
  end
end
```

### 4. Audit Logging

**Current State:** Basic structured logging exists but no audit trail.

**Recommendation:**

```elixir
# New resource: lib/piano/core/audit_log.ex
defmodule Piano.Core.AuditLog do
  use Ash.Resource,
    domain: Piano.Core,
    data_layer: AshSqlite.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :action, :atom  # :interaction_created, :command_executed, :file_changed
    attribute :actor_type, :atom  # :user, :agent, :system
    attribute :actor_id, :string
    attribute :resource_type, :string
    attribute :resource_id, :string
    attribute :metadata, :map  # Sanitized context
    attribute :ip_address, :string
    timestamps()
  end
end
```

## High Priority (P1)

### 5. Telegram Webhook Security

**Current:** Uses polling (safer), but if webhooks added:

```elixir
# Verify Telegram webhook signatures
def verify_telegram_signature(conn, bot_token) do
  signature = get_req_header(conn, "x-telegram-bot-api-secret-token")
  expected = :crypto.hash(:sha256, bot_token)
  
  Plug.Crypto.secure_compare(signature, expected)
end
```

### 6. Browser Agent Isolation

**Current Issue:** BrowserAgent runs in single session without isolation.

**Recommendation:**
- Separate browser sessions per user/thread
- Containerized browser instances (selenoid/grid)
- Sandbox restrictions: disable downloads, limit file access

### 7. MCP Endpoint Authentication

**Current:** `/mcp` endpoint exposed without authentication.

**Recommendation:**
```elixir
# lib/piano_web/router.ex
scope "/mcp" do
  pipe_through [:api, :mcp_auth]
  
  forward "/", AshAi.Mcp.Router, ...
end

# Add authentication plug
defmodule PianoWeb.McpAuth do
  def init(opts), do: opts
  
  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> verify_mcp_token(token, conn)
      _ -> send_resp(conn, 401, "Unauthorized") |> halt()
    end
  end
end
```

### 8. Secrets Management

**Current:** All secrets via environment variables.

**Recommendation:**
- Support for secret management systems (AWS Secrets Manager, Vault)
- Encrypted credentials in database for user-specific tokens
- Rotation tracking

## Medium Priority (P2)

### 9. Content Security Policy

**For Web Interface:**
```elixir
# lib/piano_web/router.ex
plug :put_secure_browser_headers, %{
  "content-security-policy" => "default-src 'self'; script-src 'self' 'unsafe-inline';"
}
```

### 10. SQL Injection Prevention

**Current:** Ash framework provides protection, but raw SQL in migrations.

**Recommendation:**
- Review all `fragment()` usage in queries
- Use parameterized queries exclusively

### 11. Command Injection Prevention

**Current:** Codex approval system exists but no additional validation.

**Recommendation:**
```elixir
# lib/piano/codex/client.ex - Enhanced approval
defp approval_decision(method, params) do
  command = params["command"] || []
  
  # Block dangerous commands
  if contains_dangerous_command?(command) do
    Logger.warning("Blocked dangerous command: #{inspect(command)}")
    "decline"
  else
    # Existing logic
    ...
  end
end

defp contains_dangerous_command?(command) do
  blocked = ["rm -rf /", "mkfs", "dd if=", ":(){:|:&};:"]
  cmd_str = Enum.join(command, " ")
  
  Enum.any?(blocked, &String.contains?(cmd_str, &1))
end
```

### 12. Session Management

**Current:** No session concept for web interface.

**Recommendation:**
- Implement Phoenix Token-based sessions
- Session timeout (e.g., 24 hours)
- Concurrent session limits per user

## Implementation Priority

| Priority | Item | Effort | Risk Level |
|----------|------|--------|------------|
| P0 | Admin Token Security | 2h | Critical |
| P0 | Input Validation | 4h | High |
| P0 | Rate Limiting | 4h | High |
| P1 | Audit Logging | 8h | Medium |
| P1 | MCP Auth | 4h | High |
| P1 | Browser Isolation | 16h | Medium |
| P2 | CSP Headers | 2h | Low |
| P2 | Command Validation | 4h | Medium |
