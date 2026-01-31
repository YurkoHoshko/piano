%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/"]
      },
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        extra: [
          {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 60},
          {Credo.Check.Refactor.Nesting, max_nesting: 4}
        ]
      }
    }
  ]
}
