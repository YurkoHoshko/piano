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
