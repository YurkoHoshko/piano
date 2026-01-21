defmodule Piano.Repo.Migrations.AddPendingMessageIdToTelegramSessions do
  use Ecto.Migration

  def up do
    alter table(:telegram_sessions) do
      add :pending_message_id, :bigint
    end
  end

  def down do
    alter table(:telegram_sessions) do
      remove :pending_message_id
    end
  end
end
