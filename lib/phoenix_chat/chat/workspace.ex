defmodule PhoenixChat.Chat.Workspace do
  use Ecto.Schema
  import Ecto.Changeset

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    has_many :channels, PhoenixChat.Chat.Channel

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for creating/updating a workspace."
  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
  end
end
