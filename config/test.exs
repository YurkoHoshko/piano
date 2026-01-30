import Config

config :piano, Piano.Repo,
  database: Path.expand("../piano_test.db", __DIR__),
  pool_size: 5

config :piano, PianoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_at_least_64_bytes_long_for_testing_only_piano_app_x",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view, :enable_expensive_runtime_checks, true

config :piano, dev_routes: true
config :piano, test_routes: true

config :piano, :codex_replay_paths, []

# Default to the local replay profile in tests; individual tests can override.
#
# Note: the Codex integration test overrides CODEX_HOME and OPENAI_BASE_URL.
config :piano, Piano.Codex.Config,
  codex_command: "codex",
  current_profile: :replay,
  allowed_profiles: [:replay]

# Use mock Telegram API for tests
config :piano, :telegram_api_impl, Piano.Telegram.API.Mock
