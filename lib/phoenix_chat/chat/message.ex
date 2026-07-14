defmodule PhoenixChat.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :body, :string
    field :reply_count, :integer, default: 0
    field :last_reply_at, :utc_datetime_usec
    field :edited_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec
    field :also_sent_to_channel, :boolean, default: false

    belongs_to :channel, PhoenixChat.Chat.Channel
    belongs_to :user, PhoenixChat.Accounts.User
    belongs_to :parent, PhoenixChat.Chat.Message, foreign_key: :parent_message_id
    has_many :replies, PhoenixChat.Chat.Message, foreign_key: :parent_message_id
    has_many :reactions, PhoenixChat.Chat.MessageReaction

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body, :parent_message_id, :also_sent_to_channel])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 4000)
  end

  def edit_changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, fn
      nil -> nil
      v -> String.trim(v)
    end)
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 4000)
    |> put_change(:edited_at, DateTime.utc_now())
  end
end
