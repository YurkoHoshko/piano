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


