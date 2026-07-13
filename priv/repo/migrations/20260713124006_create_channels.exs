defmodule PhoenixChat.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :topic, :string
      add :kind, :string, null: false, default: "channel"
      add :dm_key, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channels, [:name],
             where: "kind = 'channel'",
             name: :channels_channel_name_index
           )

    create unique_index(:channels, [:slug])
    create unique_index(:channels, [:dm_key])

    create table(:channel_memberships) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :last_read_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channel_memberships, [:channel_id, :user_id])
    create index(:channel_memberships, [:user_id])
  end
end
