defmodule PhoenixChat.Repo.Migrations.CreateWorkspacesAndBackfillChannels do
  use Ecto.Migration

  def up do
    create table(:workspaces) do
      add :name, :string, null: false
      add :slug, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspaces, [:slug])

    alter table(:channels) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
    end

    flush()

    now = NaiveDateTime.utc_now()

    %Postgrex.Result{rows: [[workspace_id]]} =
      repo().query!(
        "INSERT INTO workspaces (name, slug, inserted_at, updated_at) VALUES ($1, $2, $3, $3) RETURNING id",
        ["Tenderr", "tenderr", now]
      )

    repo().query!(
      "UPDATE channels SET workspace_id = $1 WHERE workspace_id IS NULL",
      [workspace_id]
    )

    execute("ALTER TABLE channels ALTER COLUMN workspace_id SET NOT NULL")

    create index(:channels, [:workspace_id])
  end

  def down do
    alter table(:channels) do
      remove :workspace_id
    end

    drop table(:workspaces)
  end
end
