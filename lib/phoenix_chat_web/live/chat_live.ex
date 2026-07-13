defmodule PhoenixChatWeb.ChatLive do
  use PhoenixChatWeb, :live_view

  import PhoenixChatWeb.ChatComponents

  alias PhoenixChat.Chat
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
       conversation_title: nil,
       newest: nil,
       oldest: nil,
       older_cursor: nil,
       messages_empty?: true,
       form: empty_form(),
       online: online_ids(),
       show_dm_modal: false,
       dm_candidates: []
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
    {:noreply, open_conversation(socket, channel)}
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
        {:noreply, assign(socket, form: empty_form())}

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
          stream_insert(acc, :messages, entry, at: idx)
        end)

      # The old top message now has a predecessor — regroup it in place.
      socket =
        if boundary do
          rebuilt = build_entry(boundary, List.last(older), me.id)
          stream_insert(socket, :messages, rebuilt, at: length(entries))
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
         |> stream_insert(:messages, entry)}

      message.user_id == me.id ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> update(:channels, &bump_unread(&1, message.channel_id))
         |> update(:dms, &bump_unread(&1, message.channel_id))}
    end
  end

  # Reaction UI lands in Task 14; ignore the broadcast until then.
  def handle_info({:reaction_changed, _message}, socket), do: {:noreply, socket}

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

  defp open_conversation(socket, channel) do
    user = current_user(socket)
    title = conversation_title(channel, user)
    Chat.mark_read(user, channel)
    {messages, older_cursor} = Chat.list_messages(channel)

    socket
    |> assign(
      active: channel,
      conversation_title: title,
      older_cursor: older_cursor,
      newest: List.last(messages),
      oldest: List.first(messages),
      messages_empty?: messages == [],
      channels: clear_unread(socket.assigns.channels, channel.id),
      dms: clear_unread(socket.assigns.dms, channel.id),
      page_title: title,
      show_dm_modal: false,
      form: empty_form()
    )
    |> stream(:messages, build_entries(messages, user.id), reset: true)
  end

  defp conversation_title(%{kind: :dm} = channel, me),
    do: "@" <> Chat.dm_other_user(channel, me).username

  defp conversation_title(channel, _me), do: "#" <> channel.name

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

    %{
      id: message.id,
      user_id: message.user_id,
      username: message.user.username,
      body: message.body,
      inserted_at: message.inserted_at,
      compact?: compact?,
      day_break?: not same_day,
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

  defp current_user(socket), do: socket.assigns.current_scope.user

  defp online_ids do
    Presence.list(@online_topic) |> Map.keys() |> MapSet.new()
  end
end
