defmodule Piano.MixProject do
  use Mix.Project

  def project do
    [
      app: :piano,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      releases: [
        piano: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent],
          steps: [:assemble, :tar]
        ]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.post": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      mod: {Piano.Application, []},
      extra_applications: [:logger, :runtime_tools, :req, :finch]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},

      # Ash Framework (pinned < 3.13.0 for splode 0.2.x compatibility with req_llm)
      {:ash, "~> 3.0 and < 3.13.0"},
      {:ash_sqlite, "~> 0.2"},
      {:ash_phoenix, "~> 2.0"},

      # Pipeline
      {:gen_stage, "~> 1.2"},

      # HTTP client (used by ExGram adapter)
      {:req, "~> 0.5"},
      {:broadway, "~> 1.0"},

      # Multipart form data for file uploads
      {:multipart, "~> 0.4"},

      # Tools
      {:floki, "~> 0.37"},
      {:wallaby, "~> 0.30"},

      # Testing
      {:mox, "~> 1.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:sourceror, "~> 1.7", only: [:dev, :test]},

      # Telegram
      {:ex_gram, "~> 0.57"},

      # AI / MCP
      {:ash_ai, github: "ash-project/ash_ai"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind piano", "esbuild piano"],
      "assets.deploy": [
        "tailwind piano --minify",
        "esbuild piano --minify",
        "phx.digest"
      ],
      "ash.setup": ["ash.migrate"],
      "ash.reset": ["ash.drop", "ash.setup"]
    ]
  end
end
