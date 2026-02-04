defmodule Piano.Scheduler do
  @moduledoc """
  Quantum scheduler for background jobs.

  Configured via `config :piano, Piano.Scheduler, jobs: [...]`
  """
  use Quantum, otp_app: :piano
end
