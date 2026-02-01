import Config

if System.get_env("PHX_SERVER") do
  config :piano, PianoWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/piano/piano.db
      """

  config :piano, Piano.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :piano, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Browser agent configuration (runtime)
  config :piano,
         :browser_agent_enabled,
         System.get_env("BROWSER_AGENT_ENABLED", "false") == "true"

  config :piano,
         :browser_agent_driver,
         String.to_atom(System.get_env("BROWSER_AGENT_DRIVER", "chrome"))

  config :piano, :browser_agent_config_path, System.get_env("BROWSER_AGENT_CONFIG_PATH")

  config :piano, PianoWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    check_origin: false,
    secret_key_base: secret_key_base

  # Telegram bot configuration
  telegram_token = System.get_env("TELEGRAM_BOT_TOKEN")
  telegram_username = System.get_env("TELEGRAM_BOT_USERNAME")

  config :piano, :telegram,
    bot_token: telegram_token,
    bot_username: telegram_username,
    enabled: telegram_token != nil

  config :ex_gram, token: telegram_token

  # Transcription service configuration (Qwen3-ASR via Pythonx)
  config :piano, :transcription,
    enabled: System.get_env("TRANSCRIPTION_ENABLED", "true") == "true",
    model: System.get_env("TRANSCRIPTION_MODEL", "Qwen/Qwen3-ASR-0.6B"),
    use_local: System.get_env("TRANSCRIPTION_USE_LOCAL", "true") == "true"
end
