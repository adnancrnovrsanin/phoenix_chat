defmodule PhoenixChat.Chat.ChannelMembership do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channel_memberships" do
    belongs_to :channel, PhoenixChat.Chat.Channel
    belongs_to :user, PhoenixChat.Accounts.User
    field :last_read_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:channel_id, :user_id])
    |> validate_required([:channel_id, :user_id])
    |> put_initial_last_read()
    |> unique_constraint([:channel_id, :user_id])
  end

  defp put_initial_last_read(changeset) do
    if get_field(changeset, :last_read_at) do
      changeset
    else
      put_change(changeset, :last_read_at, DateTime.utc_now())
    end
  end
end
