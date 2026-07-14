defmodule PhoenixChat.Chat.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channels" do
    field :name, :string
    field :slug, :string
    field :topic, :string
    field :kind, Ecto.Enum, values: [:channel, :dm], default: :channel
    field :dm_key, :string

    belongs_to :workspace, PhoenixChat.Chat.Workspace
    has_many :memberships, PhoenixChat.Chat.ChannelMembership

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for creating a public channel (kind :channel). Slug mirrors the name."
  def create_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :topic])
    |> update_change(:name, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 40)
    |> validate_format(:name, ~r/^[a-z0-9\-]+$/,
      message: "only lowercase letters, numbers and dashes"
    )
    |> validate_length(:topic, max: 120)
    |> put_slug_from_name()
    |> validate_required([:workspace_id])
    |> unique_constraint(:name, name: :channels_channel_name_index)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:workspace_id)
  end

  defp put_slug_from_name(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, name)
    end
  end
end
