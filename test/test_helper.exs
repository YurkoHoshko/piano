ExUnit.start()

case Application.ensure_all_started(:piano) do
  {:ok, _} -> :ok
  {:error, {:already_started, :piano}} -> :ok
  {:error, reason} -> raise "Failed to start :piano app for tests: #{inspect(reason)}"
end

# Define Mox mock for Telegram API
Mox.defmock(Piano.Telegram.API.Mock, for: Piano.Telegram.API)
