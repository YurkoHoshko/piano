ExUnit.start()

case Application.ensure_all_started(:piano) do
  {:ok, _} -> :ok
  {:error, {:already_started, :piano}} -> :ok
  {:error, reason} -> raise "Failed to start :piano app for tests: #{inspect(reason)}"
end
