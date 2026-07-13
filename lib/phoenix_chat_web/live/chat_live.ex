defmodule PhoenixChatWeb.ChatLive do
  use PhoenixChatWeb, :live_view

  import PhoenixChatWeb.ChatComponents

  alias PhoenixChat.Chat

  @impl true
  def mount(_params, _session, socket) do
    user = current_user(socket)
    channels = Chat.list_joined_channels(user)
    dms = Chat.list_dm_channels(user)

    if connected?(socket) do
      for %{channel: channel} <- channels ++ dms, do: Chat.subscribe(channel)
    end

    {:ok,
     socket
     |> assign(
       channels: channels,
       dms: dms,
       active: nil,
       conversation_title: nil,
       newest: nil,
       older_cursor: nil,
       messages_empty?: true,
       form: empty_form()
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
  def handle_info({:new_message, message}, socket) do
    %{active: active} = socket.assigns
    me = current_user(socket)

    if active && message.channel_id == active.id do
      Chat.mark_read(me, active)
      entry = build_entry(message, socket.assigns.newest, me.id)

      {:noreply,
       socket
       |> assign(newest: message, messages_empty?: false)
       |> stream_insert(:messages, entry)}
    else
      # Sidebar unread bump lands in Task 12.
      {:noreply, socket}
    end
  end

  # Reaction UI lands in Task 14; ignore the broadcast until then.
  def handle_info({:reaction_changed, _message}, socket), do: {:noreply, socket}

  def handle_info({:redirect_index, path}, socket) do
    {:noreply, push_patch(socket, to: path)}
  end

  ## Helpers

  defp open_conversation(socket, channel) do
    user = current_user(socket)
    Chat.mark_read(user, channel)
    {messages, older_cursor} = Chat.list_messages(channel)

    socket
    |> assign(
      active: channel,
      conversation_title: "#" <> channel.name,
      older_cursor: older_cursor,
      newest: List.last(messages),
      messages_empty?: messages == [],
      channels: clear_unread(socket.assigns.channels, channel.id),
      dms: clear_unread(socket.assigns.dms, channel.id),
      page_title: "#" <> channel.name,
      form: empty_form()
    )
    |> stream(:messages, build_entries(messages, user.id), reset: true)
  end

  defp build_entries(messages, me_id) do
    {entries, _prev} =
      Enum.map_reduce(messages, nil, fn message, prev ->
        {build_entry(message, prev, me_id), message}
      end)

    entries
  end

  # `prev` (the chronologically previous message) powers grouping in Task 11.
  defp build_entry(message, _prev, me_id) do
    %{
      id: message.id,
      user_id: message.user_id,
      username: message.user.username,
      body: message.body,
      inserted_at: message.inserted_at,
      reactions: Chat.summarize_reactions(message.reactions, me_id)
    }
  end

  defp clear_unread(rows, channel_id) do
    Enum.map(rows, fn
      %{channel: %{id: ^channel_id}} = row -> %{row | unread: 0}
      row -> row
    end)
  end

  defp empty_form, do: to_form(%{"body" => ""}, as: :message)

  defp current_user(socket), do: socket.assigns.current_scope.user
end
