defmodule PhoenixChat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:channel_id, :id])
  end
end
