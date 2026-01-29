%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/"]
      },
      strict: false,
      parse_timeout: 5000,
      color: true
    }
  ]
}
