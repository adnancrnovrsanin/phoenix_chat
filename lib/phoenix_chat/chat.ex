defmodule PhoenixChat.Chat do
  @moduledoc """
  Channels, direct messages, messages, reactions, unread tracking.
  """

  import Ecto.Query, warn: false

  alias PhoenixChat.Repo
  alias PhoenixChat.Accounts.User
  alias PhoenixChat.Chat.{Channel, ChannelMembership}

  ## PubSub

  @doc "Subscribes the caller to the channel's realtime topic."
  def subscribe(%Channel{} = channel) do
    Phoenix.PubSub.subscribe(PhoenixChat.PubSub, topic(channel))
  end

  defp topic(%Channel{id: id}), do: "chat:channel:#{id}"

  ## Channels

  def get_channel!(id), do: Repo.get!(Channel, id)

  def get_channel_by_slug!(slug), do: Repo.get_by!(Channel, slug: slug)

  def create_channel(%User{} = creator, attrs) do
    result =
      %Channel{kind: :channel}
      |> Channel.create_changeset(attrs)
      |> Repo.insert()

    # Remap slug constraint errors to name field for consistency
    result = case result do
      {:error, %{errors: [{:slug, error} | rest]} = changeset} ->
        {:error, %{changeset | errors: [{:name, error} | rest]}}
      other ->
        other
    end

    with {:ok, channel} <- result do
      {:ok, _membership} = join_channel(creator, channel)
      {:ok, channel}
    end
  end

  @doc "Idempotent: joining twice is a no-op."
  def join_channel(%User{} = user, %Channel{} = channel) do
    %ChannelMembership{}
    |> ChannelMembership.changeset(%{user_id: user.id, channel_id: channel.id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:channel_id, :user_id])
  end

  def member?(%User{} = user, %Channel{} = channel) do
    Repo.exists?(
      from m in ChannelMembership,
        where: m.user_id == ^user.id and m.channel_id == ^channel.id
    )
  end

  def list_joined_channels(%User{} = user), do: memberships_with_unread(user, :channel)

  def list_browsable_channels(%User{} = user) do
    joined_ids =
      from m in ChannelMembership, where: m.user_id == ^user.id, select: m.channel_id

    Repo.all(
      from c in Channel,
        where: c.kind == :channel and c.id not in subquery(joined_ids),
        order_by: [asc: c.name]
    )
  end

  def ensure_general_channel! do
    case Repo.get_by(Channel, slug: "general") do
      nil ->
        Repo.insert!(%Channel{kind: :channel, name: "general", slug: "general"})

      %Channel{} = channel ->
        channel
    end
  end

  # Unread counting joins messages once that table exists (Task 6/7). Until then
  # the left join below is against an always-empty relation via a false condition.
  defp memberships_with_unread(user, kind) do
    Repo.all(
      from m in ChannelMembership,
        join: c in Channel,
        on: c.id == m.channel_id,
        where: m.user_id == ^user.id and c.kind == ^kind,
        order_by: [asc: c.name],
        select: %{channel: c, unread: 0}
    )
  end
end
