defmodule PhoenixChat.Chat do
  @moduledoc """
  Channels, direct messages, messages, reactions, unread tracking.
  """

  @reaction_palette ~w(👍 ❤️ 😂 🎉 👀 ✅ 🔥 🙏)

  @default_workspace_name "Tenderr"

  import Ecto.Query, warn: false

  alias PhoenixChat.Repo
  alias PhoenixChat.Accounts.User
  alias PhoenixChat.Chat.{Channel, ChannelMembership, Message, MessageReaction, Workspace}

  ## PubSub

  @doc "Subscribes the caller to the channel's realtime topic."
  def subscribe(%Channel{} = channel) do
    Phoenix.PubSub.subscribe(PhoenixChat.PubSub, topic(channel))
  end

  defp topic(%Channel{id: id}), do: "chat:channel:#{id}"

  defp broadcast!(%Channel{} = channel, event) do
    Phoenix.PubSub.broadcast!(PhoenixChat.PubSub, topic(channel), event)
  end

  ## Workspaces

  @doc """
  Idempotent get-or-create of the single default workspace (slug "tenderr").
  Race-safe like `ensure_general_channel!/0`.
  """
  def default_workspace! do
    case Repo.get_by(Workspace, slug: "tenderr") do
      %Workspace{} = workspace ->
        workspace

      nil ->
        case Repo.insert(%Workspace{name: @default_workspace_name, slug: "tenderr"},
               on_conflict: :nothing,
               conflict_target: :slug
             ) do
          {:ok, %Workspace{id: nil}} ->
            # Lost the race — the row was inserted by a concurrent caller; re-fetch.
            Repo.get_by!(Workspace, slug: "tenderr")

          {:ok, %Workspace{} = workspace} ->
            workspace
        end
    end
  end

  ## Channels

  def get_channel!(id), do: Repo.get!(Channel, id)

  def get_channel_by_slug!(slug), do: Repo.get_by!(Channel, slug: slug)

  @doc """
  Gets a channel by slug, returning nil if it does not exist.
  """
  def get_channel_by_slug(slug), do: Repo.get_by(Channel, slug: slug)

  def create_channel(%User{} = creator, attrs) do
    workspace = default_workspace!()

    result =
      %Channel{kind: :channel, workspace_id: workspace.id}
      |> Channel.create_changeset(attrs)
      |> Repo.insert()

    # Remap slug constraint errors to name field for consistency
    result =
      case result do
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

  @doc """
  Joins a public channel by id. Raises Ecto.NoResultsError if the id does not
  belong to a public (kind :channel) channel — DMs cannot be joined this way.
  """
  def join_public_channel(%User{} = user, channel_id) do
    channel = Repo.get_by!(Channel, id: channel_id, kind: :channel)
    {:ok, _} = join_channel(user, channel)
    channel
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
    workspace = default_workspace!()

    joined_ids =
      from m in ChannelMembership, where: m.user_id == ^user.id, select: m.channel_id

    Repo.all(
      from c in Channel,
        where:
          c.kind == :channel and c.workspace_id == ^workspace.id and
            c.id not in subquery(joined_ids),
        order_by: [asc: c.name]
    )
  end

  def ensure_general_channel! do
    case Repo.get_by(Channel, slug: "general") do
      %Channel{} = channel ->
        channel

      nil ->
        workspace = default_workspace!()

        case Repo.insert(
               %Channel{
                 kind: :channel,
                 name: "general",
                 slug: "general",
                 workspace_id: workspace.id
               },
               on_conflict: :nothing,
               conflict_target: :slug
             ) do
          {:ok, %Channel{id: nil}} ->
            # Lost the race — the row was inserted by a concurrent caller; re-fetch.
            Repo.get_by!(Channel, slug: "general")

          {:ok, %Channel{} = channel} ->
            channel
        end
    end
  end

  def join_general(%User{} = user) do
    join_channel(user, ensure_general_channel!())
  end

  defp memberships_with_unread(user, kind) do
    workspace = default_workspace!()

    Repo.all(
      from m in ChannelMembership,
        join: c in Channel,
        on: c.id == m.channel_id,
        where: m.user_id == ^user.id and c.kind == ^kind and c.workspace_id == ^workspace.id,
        left_join: msg in Message,
        on:
          msg.channel_id == c.id and msg.inserted_at > m.last_read_at and
            msg.user_id != ^user.id and is_nil(msg.parent_message_id),
        group_by: c.id,
        order_by: [asc: c.name],
        select: %{channel: c, unread: count(msg.id)}
    )
  end

  ## Messages

  def get_message!(id) do
    Message |> Repo.get!(id) |> Repo.preload([:user, :reactions])
  end

  def send_message(%User{} = user, %Channel{} = channel, attrs) do
    if member?(user, channel) do
      changeset = Message.changeset(%Message{user_id: user.id, channel_id: channel.id}, attrs)

      with {:ok, changeset} <- validate_parent(changeset, channel),
           {:ok, message} <- Repo.insert(changeset) do
        message = %{message | user: user, reactions: []}

        case message.parent_message_id do
          nil ->
            broadcast!(channel, {:new_message, message})
            {:ok, message}

          parent_id ->
            now = DateTime.utc_now()

            from(m in Message, where: m.id == ^parent_id)
            |> Repo.update_all(inc: [reply_count: 1], set: [last_reply_at: now])

            broadcast!(channel, {:new_message, message})
            broadcast!(channel, {:message_updated, get_message!(parent_id)})
            {:ok, message}
        end
      end
    else
      {:error, :not_a_member}
    end
  end

  defp validate_parent(changeset, %Channel{} = channel) do
    case Ecto.Changeset.get_change(changeset, :parent_message_id) do
      nil ->
        {:ok, changeset}

      parent_id ->
        if Repo.exists?(
             from m in Message, where: m.id == ^parent_id and m.channel_id == ^channel.id
           ) do
          {:ok, changeset}
        else
          {:error,
           Ecto.Changeset.add_error(
             changeset,
             :parent_message_id,
             "does not belong to this channel"
           )}
        end
    end
  end

  @doc """
  Newest page of messages in ascending order plus a cursor for older pages.
  Cursor is nil when there is nothing older.
  """
  def list_messages(%Channel{} = channel, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before_id)

    query =
      from m in Message,
        where: m.channel_id == ^channel.id,
        where: is_nil(m.parent_message_id) or m.also_sent_to_channel == true,
        order_by: [desc: m.id],
        limit: ^limit,
        preload: [:user, :reactions]

    query = if before_id, do: where(query, [m], m.id < ^before_id), else: query

    messages = query |> Repo.all() |> Enum.reverse()

    cursor =
      if length(messages) == limit, do: List.first(messages).id, else: nil

    {messages, cursor}
  end

  @doc """
  Replies to a thread parent in ascending order plus a cursor for older pages.
  Cursor is nil when there is nothing older.
  """
  def list_thread_replies(%Message{} = parent, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before_id)

    query =
      from m in Message,
        where: m.parent_message_id == ^parent.id,
        order_by: [desc: m.id],
        limit: ^limit,
        preload: [:user, :reactions]

    query = if before_id, do: where(query, [m], m.id < ^before_id), else: query

    messages = query |> Repo.all() |> Enum.reverse()

    cursor =
      if length(messages) == limit, do: List.first(messages).id, else: nil

    {messages, cursor}
  end

  @doc """
  Edits a message's body. Author-only: returns `{:error, :unauthorized}` for
  anyone else. On success stamps `edited_at` (via `Message.edit_changeset/2`)
  and broadcasts `{:message_updated, message}` with `:user`/`:reactions` reloaded.
  """
  def update_message(%User{} = user, %Message{} = message, attrs) do
    if message.user_id == user.id do
      changeset = Message.edit_changeset(message, attrs)

      with {:ok, _} <- Repo.update(changeset) do
        updated = get_message!(message.id)
        broadcast!(get_channel!(message.channel_id), {:message_updated, updated})
        {:ok, updated}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Soft-deletes a message. Author-only: returns `{:error, :unauthorized}` for
  anyone else. Sets `deleted_at`; the row and any thread replies are retained.
  Broadcasts `{:message_deleted, message}` so clients render a tombstone.
  """
  def delete_message(%User{} = user, %Message{} = message) do
    if message.user_id == user.id do
      from(m in Message, where: m.id == ^message.id)
      |> Repo.update_all(set: [deleted_at: DateTime.utc_now()])

      deleted = get_message!(message.id)
      broadcast!(get_channel!(message.channel_id), {:message_deleted, deleted})
      {:ok, deleted}
    else
      {:error, :unauthorized}
    end
  end

  ## Unread

  @doc """
  Returns the membership's `last_read_at` for `user` in `channel`, or `nil`
  when there is no membership. Read this before `mark_read/2` so the caller
  can place the unread divider at the reader's last-seen position.
  """
  def last_read_at(%User{} = user, %Channel{} = channel) do
    Repo.one(
      from m in ChannelMembership,
        where: m.user_id == ^user.id and m.channel_id == ^channel.id,
        select: m.last_read_at
    )
  end

  def mark_read(%User{} = user, %Channel{} = channel) do
    now = DateTime.utc_now()

    from(m in ChannelMembership,
      where: m.user_id == ^user.id and m.channel_id == ^channel.id
    )
    |> Repo.update_all(set: [last_read_at: now])

    :ok
  end

  def unread_count(%User{} = user, %Channel{} = channel) do
    case Repo.get_by(ChannelMembership, user_id: user.id, channel_id: channel.id) do
      nil ->
        0

      %ChannelMembership{last_read_at: last_read_at} ->
        Repo.aggregate(
          from(m in Message,
            where:
              m.channel_id == ^channel.id and m.inserted_at > ^last_read_at and
                m.user_id != ^user.id and is_nil(m.parent_message_id)
          ),
          :count
        )
    end
  end

  ## Direct messages

  @doc """
  Returns the DM channel between two distinct users, creating it (and both
  memberships) on first use. Safe under races via the unique dm_key index.
  """
  def get_or_create_dm!(%User{id: a_id} = a, %User{id: b_id} = b) when a_id != b_id do
    key = dm_key(a_id, b_id)

    case Repo.get_by(Channel, dm_key: key) do
      %Channel{} = channel ->
        channel

      nil ->
        workspace = default_workspace!()

        {:ok, channel} =
          Repo.transaction(fn ->
            channel =
              case Repo.insert(%Channel{
                     kind: :dm,
                     name: key,
                     slug: "dm-" <> key,
                     dm_key: key,
                     workspace_id: workspace.id
                   }) do
                {:ok, channel} -> channel
                # lost a creation race — the row exists now
                {:error, _changeset} -> Repo.get_by!(Channel, dm_key: key)
              end

            {:ok, _} = join_channel(a, channel)
            {:ok, _} = join_channel(b, channel)
            channel
          end)

        channel
    end
  end

  defp dm_key(id1, id2) when id1 <= id2, do: "#{id1}:#{id2}"
  defp dm_key(id1, id2), do: "#{id2}:#{id1}"

  def dm_other_user(%Channel{kind: :dm} = channel, %User{} = me) do
    Repo.one!(
      from u in User,
        join: m in ChannelMembership,
        on: m.user_id == u.id,
        where: m.channel_id == ^channel.id and u.id != ^me.id
    )
  end

  def list_dm_channels(%User{} = user) do
    for %{channel: channel} = row <- memberships_with_unread(user, :dm) do
      Map.put(row, :other_user, dm_other_user(channel, user))
    end
  end

  ## Reactions

  def reaction_palette, do: @reaction_palette

  def toggle_reaction(%User{} = user, %Message{} = message, emoji) do
    channel = get_channel!(message.channel_id)

    changeset =
      MessageReaction.changeset(%MessageReaction{}, %{
        emoji: emoji,
        message_id: message.id,
        user_id: user.id
      })

    cond do
      not member?(user, channel) ->
        {:error, :not_a_member}

      not changeset.valid? ->
        {:error, :invalid_emoji}

      true ->
        case Repo.get_by(MessageReaction,
               message_id: message.id,
               user_id: user.id,
               emoji: emoji
             ) do
          nil -> Repo.insert!(changeset)
          %MessageReaction{} = reaction -> Repo.delete!(reaction)
        end

        broadcast!(channel, {:reaction_changed, get_message!(message.id)})
        :ok
    end
  end

  @doc """
  Groups preloaded reactions into `%{emoji, count, mine}` rows.

  Palette emojis appear first in palette order; arbitrary emojis (from the full
  picker) follow in insertion order so reaction chips always render.
  """
  def summarize_reactions(reactions, me_id) when is_list(reactions) do
    grouped = Enum.group_by(reactions, & &1.emoji)

    palette_rows =
      for emoji <- @reaction_palette, rows = grouped[emoji], rows != nil do
        %{emoji: emoji, count: length(rows), mine: Enum.any?(rows, &(&1.user_id == me_id))}
      end

    palette_set = MapSet.new(@reaction_palette)

    arbitrary_rows =
      grouped
      |> Enum.reject(fn {emoji, _} -> MapSet.member?(palette_set, emoji) end)
      |> Enum.map(fn {emoji, rows} ->
        %{emoji: emoji, count: length(rows), mine: Enum.any?(rows, &(&1.user_id == me_id))}
      end)

    palette_rows ++ arbitrary_rows
  end

  ## Typing

  @doc """
  Broadcasts an ephemeral typing signal on the channel topic. Nothing is
  persisted; receivers show it for a few seconds and let it expire on a TTL.
  """
  def broadcast_typing(%User{} = user, %Channel{} = channel) do
    broadcast!(channel, {:typing, %{user_id: user.id, username: user.username}})
    :ok
  end
end
