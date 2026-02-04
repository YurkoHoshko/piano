# AGENTS

Documentation snapshots live in `docs/ai_docs`.

Codex App Server docs are available at `docs/ai_docs/codex_app_server.md`.
Codex config docs (basics, advanced, reference) are available at `docs/ai_docs/codex_config.md`.

## Build and Test (Piano)

All changes to piano must be validated end-to-end:

```bash
# Build the containers
docker compose build

# Start the services
docker compose up -d

# View logs
docker compose logs -f
```

**Validation requirements:**
- Changes must be released (committed/pushed)
- Containers must be built successfully
- Services must be deployed and running
- Full e2e flow must be engaged and verified

## Running Commands in Container

Use `bin/piano rpc` to execute Elixir code inside the running container:

```bash
# Basic RPC
docker compose exec piano bin/piano rpc 'IO.puts("Hello")'

# Query interactions
docker compose exec piano bin/piano rpc 'Piano.Core.Interaction |> Ash.read!() |> length() |> IO.inspect()'

# Get specific record
docker compose exec piano bin/piano rpc 'Ash.get!(Piano.Core.Interaction, "uuid-here") |> IO.inspect()'

# Query with filters (using Ash.Query)
docker compose exec piano bin/piano rpc '
require Ash.Query
Piano.Core.Interaction
|> Ash.Query.filter(status == :complete)
|> Ash.Query.limit(5)
|> Ash.read!()
|> IO.inspect()
'

# Count records
docker compose exec piano bin/piano rpc 'Piano.Core.Thread |> Ash.read!() |> length()'
```

### Common Queries

```bash
# List all threads
docker compose exec piano bin/piano rpc 'Piano.Core.Thread |> Ash.read!() |> IO.inspect()'

# List surfaces
docker compose exec piano bin/piano rpc 'Piano.Core.Surface |> Ash.read!() |> IO.inspect()'

# Check interaction status
docker compose exec piano bin/piano rpc 'Ash.get(Piano.Core.Interaction, "uuid") |> IO.inspect()'

# TaskWarrior tasks
docker compose exec piano task list
docker compose exec piano task all
docker compose exec piano task +background list
```

### Direct SQLite Access

```bash
# Open SQLite shell
docker compose exec piano sqlite3 /data/piano.db

# Common SQL
.tables
SELECT * FROM interactions ORDER BY inserted_at DESC LIMIT 5;
SELECT COUNT(*) FROM threads_v2;
```


