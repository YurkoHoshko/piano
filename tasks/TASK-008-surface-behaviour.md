# TASK-008: Surface Behaviour

**Status:** pending  
**Dependencies:** none  
**Phase:** 3 - Surface Protocol

## Description
Define the Surface behaviour that all surface implementations must follow.

## Acceptance Criteria
- [ ] `Piano.Surface` behaviour module
- [ ] `@callback handle_event(surface, interaction, event) :: {:ok, term()} | {:ok, :noop}`
- [ ] Events: `:turn_started`, `:item_started`, `:item_completed`, `:agent_message_delta`, `:turn_completed`, `:approval_required`
- [ ] `@callback send_message(surface, message) :: :ok`
- [ ] `@callback send_typing(surface) :: :ok`
- [ ] `mix compile` passes

## Implementation Notes
- `surface` is the Surface struct from DB
- `interaction` is the current Interaction struct
- `event` is a tuple like `{:turn_started, data}` or `{:approval_required, approval_data}`
- For `:approval_required`, return value should be `{:ok, :accept}` or `{:ok, :decline}`
- Default implementations can return `{:ok, :noop}` for unhandled events
