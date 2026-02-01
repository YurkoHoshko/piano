import Config

config :piano,
  ecto_repos: [Piano.Repo],
  generators: [timestamp_type: :utc_datetime]

config :piano, :ash_domains, [Piano.Core, Piano.Domain]

config :piano, Piano.Codex.Config,
  codex_command: "codex",
  current_profile: :fast,
  allowed_profiles: [:smart, :fast, :expensive, :replay, :experimental, :gfq, :vision]

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
  metadata: [
    :mfa,
    :request_id,
    :interaction_id,
    :thread_id,
    :codex_thread_id,
    :chat_id,
    :error,
    :kind,
    :chat_type,
    :from_id,
    :username,
    :preview,
    :event,
    :current_profile,
    :turn_id,
    :codex_method,
    :codex_method_normalized,
    :codex_request_id,
    :status
  ]

config :phoenix, :json_library, Jason

# Admin token for dashboard access
config :piano, :admin_token, System.get_env("PIANO_ADMIN_TOKEN", "piano_admin")

# Telegram bot configuration
config :piano, :telegram,
  bot_token: System.get_env("TELEGRAM_BOT_TOKEN"),
  enabled: System.get_env("TELEGRAM_BOT_TOKEN") != nil

# ExGram configuration
config :ex_gram, token: System.get_env("TELEGRAM_BOT_TOKEN")
config :ex_gram, adapter: ExGram.Adapter.Req

# Tools configuration
config :piano, :browser_agent_enabled, System.get_env("BROWSER_AGENT_ENABLED", "false") == "true"
config :piano, :browser_agent_driver, :chrome
config :piano, :browser_agent_config_path, System.get_env("BROWSER_AGENT_CONFIG_PATH")

# Wallaby configuration (for browser agent)
config :wallaby,
  chromedriver: [
    path: System.get_env("CHROMEDRIVER_PATH", "/usr/bin/chromedriver")
  ],
  geckodriver: [
    path: System.get_env("GECKODRIVER_PATH", "/usr/local/bin/geckodriver")
  ]

import_config "#{config_env()}.exs"
