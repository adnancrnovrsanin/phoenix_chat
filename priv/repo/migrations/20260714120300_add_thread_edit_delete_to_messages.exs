defmodule PhoenixChat.Repo.Migrations.AddThreadEditDeleteToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :parent_message_id, references(:messages, on_delete: :delete_all)
      add :reply_count, :integer, null: false, default: 0
      add :last_reply_at, :utc_datetime_usec
      add :edited_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec
      add :also_sent_to_channel, :boolean, null: false, default: false
    end

    create index(:messages, [:parent_message_id, :id])
  end
end
