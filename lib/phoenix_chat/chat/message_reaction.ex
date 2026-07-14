defmodule PhoenixChat.Chat.MessageReaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "message_reactions" do
    belongs_to :message, PhoenixChat.Chat.Message
    belongs_to :user, PhoenixChat.Accounts.User
    field :emoji, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :message_id, :user_id])
    |> validate_required([:emoji, :message_id, :user_id])
    |> validate_emoji()
    |> unique_constraint([:message_id, :user_id, :emoji])
  end

  defp validate_emoji(changeset) do
    validate_change(changeset, :emoji, fn :emoji, emoji ->
      cond do
        length(String.graphemes(emoji)) != 1 -> [emoji: "must be a single emoji"]
        byte_size(emoji) > 16 -> [emoji: "is too long"]
        true -> []
      end
    end)
  end
end
