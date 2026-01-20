import Config

config :piano,
  ecto_repos: [Piano.Repo],
  generators: [timestamp_type: :utc_datetime]

config :piano, :ash_domains, [Piano.Chat, Piano.Agents, Piano.Telegram]

config :piano, PianoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PianoWeb.ErrorHTML, json: PianoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Piano.PubSub,
  live_view: [signing_salt: "piano_lv_salt"]

config :esbuild,
  version: "0.17.11",
  piano: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.3",
  piano: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time [$level] $metadata$message\n",
  metadata: [:mfa, :request_id]

config :phoenix, :json_library, Jason

# LLM configuration (llama-swap backend)
config :piano, :llm,
  base_url: System.get_env("LLAMA_SWAP_URL", "http://localhost:8000"),
  default_model: System.get_env("LLM_MODEL", "gpt-oss-20b")

# Admin token for dashboard access
config :piano, :admin_token, System.get_env("PIANO_ADMIN_TOKEN", "piano_admin")

# Telegram bot configuration
config :piano, :telegram,
  bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
  enabled: System.get_env("TELEGRAM_BOT_TOKEN") != nil

# ExGram configuration
config :ex_gram, token: System.get_env("TELEGRAM_BOT_TOKEN")

import_config "#{config_env()}.exs"
