defmodule PhoenixChat.Chat.MessageReaction do
  use Ecto.Schema

  schema "message_reactions" do
    belongs_to :message, PhoenixChat.Chat.Message
    belongs_to :user, PhoenixChat.Accounts.User
    field :emoji, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
