import Config

config :piano, Piano.Repo,
  database: Path.expand("../piano_dev.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :piano, PianoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_at_least_64_bytes_long_for_development_only_piano_app",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:piano, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:piano, ~w(--watch)]}
  ]

config :piano, PianoWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/piano_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, :debug_heex_annotations, true

config :logger, :console, format: "[$level] $message\n"
