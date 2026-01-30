defmodule Piano.Codex.Config do
  @moduledoc """
  Centralized Codex configuration for Piano.

  We rely on Codex config files (`.codex/config.toml`, `~/.codex/config.toml`)
  for the actual profile definitions (model/provider/etc).

  Piano is intentionally strict about what it controls: it only selects an
  allowlisted profile name and starts `codex app-server`.
  """

  @type profile_name :: atom()

  def codex_command! do
    Keyword.fetch!(config!(), :codex_command)
  end

  def current_profile! do
    profile = Keyword.fetch!(config!(), :current_profile)

    unless profile in allowed_profiles!() do
      raise ArgumentError,
            "current_profile #{inspect(profile)} is not in allowed_profiles: #{inspect(allowed_profiles!())}"
    end

    profile
  end

  def set_current_profile!(profile) when is_atom(profile) do
    unless profile in allowed_profiles!() do
      raise ArgumentError,
            "unknown Codex profile #{inspect(profile)}; allowed: #{inspect(allowed_profiles!())}"
    end

    Application.put_env(:piano, __MODULE__, Keyword.put(config!(), :current_profile, profile))
    :ok
  end

  def profile_names do
    allowed_profiles!()
  end

  @doc """
  Effective `codex app-server` argv for the current profile.

  We use `-c profile=<name>` to force the profile as a highest-precedence override.
  """
  def codex_args! do
    profile = current_profile!()
    ["-c", "profile=#{Atom.to_string(profile)}", "app-server"]
  end

  def allowed_profiles! do
    config!() |> Keyword.fetch!(:allowed_profiles) |> Enum.sort()
  end

  defp config! do
    Application.fetch_env!(:piano, __MODULE__)
  end
end
