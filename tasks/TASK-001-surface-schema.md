# TASK-001: Surface Schema

**Status:** done  
**Dependencies:** none  
**Phase:** 1 - Core Schemas

## Description
Create the Surface Ash resource to represent interaction endpoints (Telegram, LiveView).

## Acceptance Criteria
- [ ] `Piano.Core.Surface` Ash resource
- [ ] Attributes: `id`, `app` (:telegram/:liveview), `identifier`, `config` (map)
- [ ] Actions: `:create`, `:read`, `:get_by_app_and_identifier`
- [ ] `mix compile` passes
- [ ] Unit tests pass

## Implementation Notes
- Use AshSqlite for persistence
- `app` should be an atom enum
- `identifier` is the unique ID within that app (e.g., chat_id for Telegram)
- `config` stores app-specific settings as a map
