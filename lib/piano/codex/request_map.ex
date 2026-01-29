defmodule Piano.Codex.RequestMap do
  @moduledoc false

  @table :piano_codex_request_map

  def put(id, value) do
    ensure_table()
    :ets.insert(@table, {id, value})
    :ok
  end

  def get(id) do
    ensure_table()

    case :ets.lookup(@table, id) do
      [{^id, value}] -> {:ok, value}
      [] -> :error
    end
  end

  def pop(id) do
    ensure_table()

    case :ets.take(@table, id) do
      [{^id, value}] -> {:ok, value}
      [] -> :error
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _ -> @table
    end
  end
end
