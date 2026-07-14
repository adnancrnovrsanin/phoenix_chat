defmodule PhoenixChatWeb.ChatLive do
  use PhoenixChatWeb, :live_view

  import PhoenixChatWeb.ChatComponents

  alias PhoenixChat.Chat
  alias PhoenixChat.Chat.Channel
  alias PhoenixChat.Accounts
  alias PhoenixChatWeb.Presence

  @online_topic "presence:online"

  # Messages from the same author within this window collapse into one group.
  @compact_window_seconds 300

  @impl true
  def mount(_params, _session, socket) do
    user = current_user(socket)
    channels = Chat.list_joined_channels(user)
    dms = Chat.list_dm_channels(user)

    if connected?(socket) do
      for %{channel: channel} <- channels ++ dms, do: Chat.subscribe(channel)

      {:ok, _} =
        Presence.track(self(), @online_topic, to_string(user.id), %{username: user.username})

      Phoenix.PubSub.subscribe(PhoenixChat.PubSub, @online_topic)
    end

    {:ok,
     socket
     |> assign(
       channels: channels,
       dms: dms,
       active: nil,
       active_other: nil,
       conversation_title: nil,
       newest: nil,
       oldest: nil,
       older_cursor: nil,
       messages_empty?: true,
       form: empty_form(),
       online: online_ids(),
       show_dm_modal: false,
       dm_candidates: [],
       palette_for: nil,
       editing_id: nil,
       edit_form: nil,
       entry_meta: %{},
       emoji_picker: nil,
       gate?: false,
       show_create_modal: false,
       show_browse_modal: false,
       browsable: [],
       create_form: new_create_form()
     )
     |> stream(:messages, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    apply_action(socket, socket.assigns.live_action, params)
  end

  defp apply_action(socket, :index, _params) do
    if connected?(socket), do: send(self(), {:redirect_index, ~p"/c/general"})
    {:noreply, socket}
  end

  defp apply_action(socket, :channel, %{"slug" => slug}) do
    channel = Chat.get_channel_by_slug!(slug)
    me = current_user(socket)

    cond do
      Chat.member?(me, channel) ->
        {:noreply, open_conversation(socket, channel)}

      channel.kind == :dm ->
        # Behave as if it doesn't exist — DMs are private.
        raise Ecto.NoResultsError, queryable: Channel

      true ->
        {:noreply,
         socket
         |> assign(
           active: channel,
           active_other: nil,
           gate?: true,
           conversation_title: "#" <> channel.name,
           page_title: "#" <> channel.name,
           messages_empty?: true,
           older_cursor: nil,
           newest: nil,
           oldest: nil,
           entry_meta: %{},
           editing_id: nil,
           edit_form: nil,
           emoji_picker: nil,
           palette_for: nil
         )
         |> stream(:messages, [], reset: true)}
    end
  end

  defp apply_action(socket, :dm, %{"username" => username}) do
    me = current_user(socket)
    other = Accounts.get_user_by_username!(username)

    if other.id == me.id do
      send(self(), {:self_dm_redirect, ~p"/c/general"})
      {:noreply, socket}
    else
      channel = Chat.get_or_create_dm!(me, other)

      {:noreply,
       socket
       |> ensure_dm_row(channel, other)
       |> open_conversation(channel)}
    end
  end

  defp ensure_dm_row(socket, channel, other) do
    if Enum.any?(socket.assigns.dms, &(&1.channel.id == channel.id)) do
      socket
    else
      if connected?(socket), do: Chat.subscribe(channel)
      update(socket, :dms, &(&1 ++ [%{channel: channel, other_user: other, unread: 0}]))
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    case Chat.send_message(current_user(socket), socket.assigns.active, %{body: body}) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> assign(form: empty_form())
         |> push_event("clear-composer", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :message))}

      {:error, :not_a_member} ->
        {:noreply, put_flash(socket, :error, gettext("You are not a member of this channel"))}
    end
  end

  @impl true
  def handle_event("load_older", _params, socket) do
    %{older_cursor: cursor, active: channel, oldest: boundary} = socket.assigns

    if cursor do
      me = current_user(socket)
      {older, next_cursor} = Chat.list_messages(channel, before_id: cursor)
      entries = build_entries(older, me.id)

      socket =
        entries
        |> Enum.with_index()
        |> Enum.reduce(socket, fn {entry, idx}, acc ->
          insert_entry(acc, entry, at: idx)
        end)

      # The old top message now has a predecessor — regroup it in place.
      socket =
        if boundary do
          rebuilt = build_entry(boundary, List.last(older), me.id)
          insert_entry(socket, rebuilt, at: length(entries))
        else
          socket
        end

      {:noreply,
       assign(socket,
         older_cursor: next_cursor,
         oldest: List.first(older) || boundary
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"message-id" => id, "emoji" => emoji}, socket) do
    message = Chat.get_message!(id)
    _ = Chat.toggle_reaction(current_user(socket), message, emoji)
    {:noreply, socket}
  end

  def handle_event("open_palette", %{"message-id" => id}, socket) do
    id = String.to_integer(id)
    prev = socket.assigns.palette_for
    palette_for = if prev == id, do: nil, else: id
    socket = assign(socket, palette_for: palette_for)

    # Stream items only re-render when explicitly inserted; force re-render
    # of the newly opened entry (and the previously open one, if any).
    socket =
      case Map.get(socket.assigns.entry_meta, id) do
        nil -> socket
        entry -> stream_insert(socket, :messages, entry)
      end

    socket =
      if prev && prev != id do
        case Map.get(socket.assigns.entry_meta, prev) do
          nil -> socket
          entry -> stream_insert(socket, :messages, entry)
        end
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("pick_reaction", params, socket) do
    prev = socket.assigns.palette_for
    {:noreply, socket} = handle_event("toggle_reaction", params, socket)
    socket = assign(socket, palette_for: nil)

    socket =
      case prev && Map.get(socket.assigns.entry_meta, prev) do
        nil -> socket
        entry -> stream_insert(socket, :messages, entry)
      end

    {:noreply, socket}
  end

  def handle_event("edit_message", %{"message-id" => id}, socket) do
    message = Chat.get_message!(String.to_integer(id))
    me = current_user(socket)

    if message.user_id == me.id and is_nil(message.deleted_at) do
      form = to_form(%{"body" => message.body}, as: :message)

      {:noreply,
       socket
       |> assign(editing_id: message.id, edit_form: form)
       |> reinsert_entry(message.id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    case socket.assigns.editing_id do
      nil ->
        {:noreply, socket}

      id ->
        {:noreply,
         socket
         |> assign(editing_id: nil, edit_form: nil)
         |> reinsert_entry(id)}
    end
  end

  def handle_event("save_edit", %{"message" => %{"body" => body}}, socket) do
    case socket.assigns.editing_id do
      nil ->
        {:noreply, socket}

      id ->
        message = Chat.get_message!(id)

        case Chat.update_message(current_user(socket), message, %{body: body}) do
          {:ok, _message} ->
            # The {:message_updated, msg} broadcast re-renders the entry for
            # everyone (including this client), which also drops the edit form.
            {:noreply, assign(socket, editing_id: nil, edit_form: nil)}

          {:error, %Ecto.Changeset{} = changeset} ->
            # Show the translated first validation error as a flash and restore the message.
            msg = translate_error(elem(hd(changeset.errors), 1))

            {:noreply,
             socket
             |> assign(editing_id: nil, edit_form: nil)
             |> reinsert_entry(id)
             |> put_flash(:error, msg)}

          {:error, :unauthorized} ->
            {:noreply,
             socket
             |> assign(editing_id: nil, edit_form: nil)
             |> reinsert_entry(id)
             |> put_flash(:error, gettext("You can only edit your own messages"))}
        end
    end
  end

  def handle_event("delete_message", %{"message-id" => id}, socket) do
    message = Chat.get_message!(String.to_integer(id))

    case Chat.delete_message(current_user(socket), message) do
      {:ok, _message} ->
        # The {:message_deleted, msg} broadcast renders the tombstone for everyone.
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You can only delete your own messages"))}
    end
  end

  def handle_event("open_reaction_picker", %{"message-id" => id}, socket) do
    {:noreply,
     socket
     |> assign(emoji_picker: %{target: :reaction, message_id: id}, palette_for: nil)
     |> reinsert_entry(String.to_integer(id))}
  end

  def handle_event("open_composer_picker", _params, socket) do
    {:noreply, assign(socket, emoji_picker: %{target: :composer})}
  end

  def handle_event("close_emoji_picker", _params, socket) do
    {:noreply, assign(socket, emoji_picker: nil)}
  end

  def handle_event("draft_change", %{"message" => %{"body" => body}}, socket) do
    {:noreply, assign(socket, form: to_form(%{"body" => body}, as: :message))}
  end

  def handle_event(
        "emoji_picked",
        %{"emoji" => emoji, "target" => "reaction", "message-id" => id},
        socket
      ) do
    message = Chat.get_message!(id)
    _ = Chat.toggle_reaction(current_user(socket), message, emoji)
    # The {:reaction_changed, msg} broadcast re-renders the chip via apply_message_update/2.
    {:noreply, assign(socket, emoji_picker: nil)}
  end

  def handle_event("emoji_picked", %{"emoji" => emoji, "target" => "composer"}, socket) do
    body = socket.assigns.form.params["body"] || ""
    new_body = body <> emoji

    {:noreply,
     socket
     |> assign(form: to_form(%{"body" => new_body}, as: :message), emoji_picker: nil)
     |> push_event("set-composer-value", %{value: new_body})}
  end

  def handle_event("open_dm_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_dm_modal: true,
       dm_candidates: Accounts.list_users_except(current_user(socket))
     )}
  end

  def handle_event("close_dm_modal", _params, socket) do
    {:noreply, assign(socket, show_dm_modal: false)}
  end

  def handle_event("open_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: true, create_form: new_create_form())}
  end

  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: false)}
  end

  def handle_event("create_channel", %{"channel" => attrs}, socket) do
    case Chat.create_channel(current_user(socket), attrs) do
      {:ok, channel} ->
        if connected?(socket), do: Chat.subscribe(channel)

        {:noreply,
         socket
         |> assign(
           channels: Chat.list_joined_channels(current_user(socket)),
           show_create_modal: false
         )
         |> push_patch(to: ~p"/c/#{channel.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, create_form: to_form(changeset, as: :channel))}
    end
  end

  def handle_event("open_browse_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_browse_modal: true,
       browsable: Chat.list_browsable_channels(current_user(socket))
     )}
  end

  def handle_event("close_browse_modal", _params, socket) do
    {:noreply, assign(socket, show_browse_modal: false)}
  end

  def handle_event("join_channel", %{"channel-id" => id}, socket) do
    me = current_user(socket)

    case rescue_join_public(me, id) do
      {:ok, channel} ->
        if connected?(socket), do: Chat.subscribe(channel)

        {:noreply,
         socket
         |> assign(channels: Chat.list_joined_channels(me), show_browse_modal: false)
         |> push_patch(to: ~p"/c/#{channel.slug}")}

      {:error, :not_public} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("That channel does not exist or cannot be joined this way"))
         |> assign(show_browse_modal: false)}
    end
  end

  def handle_event("join_gated", _params, socket) do
    me = current_user(socket)
    channel = socket.assigns.active
    {:ok, _} = Chat.join_channel(me, channel)
    if connected?(socket), do: Chat.subscribe(channel)

    {:noreply,
     socket
     |> assign(channels: Chat.list_joined_channels(me))
     |> open_conversation(channel)}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    %{active: active} = socket.assigns
    me = current_user(socket)

    cond do
      active && message.channel_id == active.id ->
        Chat.mark_read(me, active)
        entry = build_entry(message, socket.assigns.newest, me.id)

        {:noreply,
         socket
         |> assign(newest: message, messages_empty?: false)
         |> insert_entry(entry)}

      message.user_id == me.id ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> update(:channels, &bump_unread(&1, message.channel_id))
         |> update(:dms, &bump_unread(&1, message.channel_id))}
    end
  end

  def handle_info({:message_updated, message}, socket) do
    {:noreply, apply_message_update(socket, message)}
  end

  def handle_info({:message_deleted, message}, socket) do
    {:noreply, apply_message_update(socket, message)}
  end

  def handle_info({:reaction_changed, message}, socket) do
    {:noreply, apply_message_update(socket, message)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, online: online_ids())}
  end

  def handle_info({:redirect_index, path}, socket) do
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_info({:self_dm_redirect, path}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, gettext("You cannot message yourself"))
     |> push_patch(to: path)}
  end

  ## Helpers

  # Re-render one message entry in place (preserving its grouping flags) when the
  # message belongs to the open channel. Used by edit/delete/reaction broadcasts.
  defp apply_message_update(socket, message) do
    %{active: active, entry_meta: entry_meta} = socket.assigns

    if active && message.channel_id == active.id do
      me = current_user(socket)
      meta = Map.get(entry_meta, message.id, %{compact?: false, day_break?: false})
      insert_entry(socket, rebuild_entry(message, meta, me.id))
    else
      socket
    end
  end

  # Stream items only re-render when explicitly inserted; force a re-render of an
  # already-known entry so it reflects the current editing_id / edit_form assigns.
  defp reinsert_entry(socket, id) do
    case Map.get(socket.assigns.entry_meta, id) do
      nil -> socket
      entry -> stream_insert(socket, :messages, entry)
    end
  end

  defp rescue_join_public(me, id) do
    channel = Chat.join_public_channel(me, id)
    {:ok, channel}
  rescue
    Ecto.NoResultsError -> {:error, :not_public}
  end

  defp open_conversation(socket, channel) do
    user = current_user(socket)
    title = conversation_title(channel, user)
    other = if channel.kind == :dm, do: Chat.dm_other_user(channel, user)
    Chat.mark_read(user, channel)
    {messages, older_cursor} = Chat.list_messages(channel)
    entries = build_entries(messages, user.id)

    socket
    |> assign(
      active: channel,
      active_other: other,
      gate?: false,
      conversation_title: title,
      older_cursor: older_cursor,
      newest: List.last(messages),
      oldest: List.first(messages),
      messages_empty?: messages == [],
      channels: clear_unread(socket.assigns.channels, channel.id),
      dms: clear_unread(socket.assigns.dms, channel.id),
      page_title: title,
      show_dm_modal: false,
      form: empty_form(),
      palette_for: nil,
      editing_id: nil,
      edit_form: nil,
      emoji_picker: nil,
      entry_meta: Map.new(entries, &{&1.id, &1})
    )
    |> stream(:messages, entries, reset: true)
  end

  defp conversation_title(%{kind: :dm} = channel, me),
    do: "@" <> Chat.dm_other_user(channel, me).username

  defp conversation_title(channel, _me), do: "#" <> channel.name

  # Streams can't be read back; remember each entry's layout flags so
  # reaction updates can re-insert without breaking grouping.
  defp insert_entry(socket, entry, opts \\ []) do
    socket
    |> update(:entry_meta, &Map.put(&1, entry.id, entry))
    |> stream_insert(:messages, entry, opts)
  end

  defp build_entries(messages, me_id) do
    {entries, _prev} =
      Enum.map_reduce(messages, nil, fn message, prev ->
        {build_entry(message, prev, me_id), message}
      end)

    entries
  end

  defp build_entry(message, prev, me_id) do
    same_day =
      prev != nil and
        DateTime.to_date(prev.inserted_at) == DateTime.to_date(message.inserted_at)

    compact? =
      same_day and prev.user_id == message.user_id and
        DateTime.diff(message.inserted_at, prev.inserted_at) < @compact_window_seconds

    message_entry_map(message, me_id, compact?, not same_day)
  end

  defp rebuild_entry(message, meta, me_id) do
    message_entry_map(message, me_id, meta.compact?, meta.day_break?)
  end

  defp message_entry_map(message, me_id, compact?, day_break?) do
    %{
      id: message.id,
      user_id: message.user_id,
      username: message.user.username,
      body: message.body,
      inserted_at: message.inserted_at,
      compact?: compact?,
      day_break?: day_break?,
      edited?: not is_nil(message.edited_at),
      deleted?: not is_nil(message.deleted_at),
      reply_count: message.reply_count,
      last_reply_at: message.last_reply_at,
      reactions: Chat.summarize_reactions(message.reactions, me_id)
    }
  end

  defp clear_unread(rows, channel_id) do
    Enum.map(rows, fn
      %{channel: %{id: ^channel_id}} = row -> %{row | unread: 0}
      row -> row
    end)
  end

  defp bump_unread(rows, channel_id) do
    Enum.map(rows, fn
      %{channel: %{id: ^channel_id}} = row -> %{row | unread: row.unread + 1}
      row -> row
    end)
  end

  defp empty_form, do: to_form(%{"body" => ""}, as: :message)

  defp new_create_form do
    to_form(Channel.create_changeset(%Channel{kind: :channel}, %{}), as: :channel)
  end

  defp current_user(socket), do: socket.assigns.current_scope.user

  defp online_ids do
    Presence.list(@online_topic) |> Map.keys() |> MapSet.new()
  end
end
