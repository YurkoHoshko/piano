• ### Modules >200 LOC (Elixir/tests)

  - lib/piano/pipeline/codex_event_consumer.ex — 879 LOC (also high branching + many multi-clause defs)
  - lib/piano/codex/client.ex — 431 LOC
  - lib/piano/test_harness/openai_replay.ex — 387 LOC
  - lib/piano/telegram/handler.ex — 375 LOC (high branching)
  - lib/piano/telegram/surface.ex — 351 LOC
  - lib/piano/telegram/bot_v2.ex — 232 LOC (many multi-clause defs)
  - test/piano/codex/codex_test.exs — 218 LOC
  - lib/piano/test_harness/codex_replay.ex — 210 LOC (many multi-clause defs)
  - lib/piano/codex.ex — 207 LOC

  ### “Complicated logic” hotspots (heuristic: branch-keyword counts)

  - lib/piano/pipeline/codex_event_consumer.ex — branches=44
  - lib/piano/telegram/handler.ex — branches=31
  - lib/piano/telegram/surface.ex — branches=28
  - lib/piano/codex/client.ex — branches=19
  - lib/piano/codex.ex — branches=17
  - lib/piano/telegram/bot_v2.ex — branches=15

  ### Lots of function head “overriding” (Elixir multi-clause defs; extra_clauses = defs - unique_names)

  - lib/piano/pipeline/codex_event_consumer.ex — extra_clauses=45 (defs=102)
  - lib/piano/telegram/bot_v2.ex — extra_clauses=17 (defs=23)
  - lib/piano/test_harness/codex_replay.ex — extra_clauses=17 (defs=35)
  - lib/piano/codex/client.ex — extra_clauses=16 (defs=45)
  - lib/piano/test_harness/openai_replay.ex — extra_clauses=13 (defs=29)
  - lib/piano/telegram/surface.ex — extra_clauses=13 (defs=36)
  - lib/piano/telegram/transcript.ex — extra_clauses=11 (defs=16)

  ### Likely generated / not worth auditing as “module”

  - priv/static/assets/app.js — 8593 LOC (built asset)
  - priv/static/assets/app.css — 1390 LOC (built asset)
  - priv/resource_snapshots/**.json — large data snapshots
