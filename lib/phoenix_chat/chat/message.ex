defmodule PhoenixChat.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :body, :string
    belongs_to :channel, PhoenixChat.Chat.Channel
    belongs_to :user, PhoenixChat.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 4000)
  end
end
