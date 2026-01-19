# Used by "mix format"
[
  import_deps: [:ash, :ash_sqlite, :ash_phoenix, :phoenix],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "lib/**/*.heex"]
]
