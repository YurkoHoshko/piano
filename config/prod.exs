import Config

config :piano, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

config :piano, PianoWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :debug
