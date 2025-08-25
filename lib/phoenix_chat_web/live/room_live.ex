defmodule PhoenixChatWeb.RoomLive do
  use PhoenixChatWeb, :live_view

  alias PhoenixChatWeb.Presence
  require Logger

  @impl true
  def mount(params, _session, socket) do
    room_id = params["room_id"] |> to_string()

    display_name =
      params["dn"]
      |> to_string()
      |> String.trim()

    if display_name == "" do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      topic = "room:#{room_id}"

      if connected?(socket) do
        Phoenix.PubSub.subscribe(PhoenixChat.PubSub, topic)
      end

      entries =
        Presence.list(topic)
        |> Enum.map(fn {id, %{metas: [meta | _]}} ->
          build_entry(id, meta)
        end)

      participants_count = length(entries)

      socket =
        socket
        |> assign(
          room_id: room_id,
          display_name: display_name,
          page_title: "Room #{room_id}",
          participants_count: participants_count,
          participants_empty?: participants_count == 0,
          chat_form: to_form(%{"text" => ""}),
          chat_sending?: false
        )
        |> stream(:messages, [], reset: true)
        |> stream(:participants, entries, reset: true)

      Logger.info("room live mounted",
        room_id: room_id,
        display_name: display_name
      )

      {:ok, socket}
    end
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: %{joins: joins, leaves: leaves}}, socket) do
    socket =
      Enum.reduce(joins, socket, fn {id, %{metas: [meta | _]}}, acc ->
        stream_insert(acc, :participants, build_entry(id, meta))
      end)

    socket =
      Enum.reduce(leaves, socket, fn {id, _}, acc ->
        stream_delete(acc, :participants, %{id: id})
      end)

    participants_count =
      socket.assigns.participants_count + map_size(joins) - map_size(leaves)

    Logger.debug("presence diff",
      room_id: socket.assigns.room_id,
      joins_count: map_size(joins),
      leaves_count: map_size(leaves),
      participants_count: participants_count
    )

    :telemetry.execute([:phoenix_chat, :presence, :diff], %{}, %{
      room_id: socket.assigns.room_id,
      joins: map_size(joins),
      leaves: map_size(leaves),
      total: participants_count
    })

    {:noreply,
     assign(socket,
       participants_count: participants_count,
       participants_empty?: participants_count == 0
     )}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "chat:msg", payload: payload, topic: _},
        socket
      ) do
    msg_id =
      "#{payload["from_id"] || "anon"}:#{payload["ts"] || System.system_time()}" <>
        ":#{:erlang.unique_integer([:monotonic])}"

    entry = %{
      id: msg_id,
      from_id: payload["from_id"],
      display_name: payload["display_name"],
      text: payload["text"],
      ts: payload["ts"]
    }

    Logger.debug("chat:msg",
      room_id: socket.assigns.room_id,
      from_id: payload["from_id"],
      display_name: payload["display_name"],
      ts: payload["ts"]
    )

    {:noreply, stream_insert(socket, :messages, entry)}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "media:update", payload: _payload},
        socket
      ) do
    # Presence diffs will refresh participant metas; no LV action needed here.
    {:noreply, socket}
  end

  defp build_entry(id, meta) do
    %{
      id: id,
      display_name: Map.get(meta, :display_name) || Map.get(meta, "display_name"),
      audio_muted: Map.get(meta, :audio_muted) || Map.get(meta, "audio_muted"),
      video_enabled: Map.get(meta, :video_enabled) || Map.get(meta, "video_enabled"),
      screensharing: Map.get(meta, :screensharing) || Map.get(meta, "screensharing")
    }
  end

  defp sanitize_text(text) do
    text
    |> to_string()
    |> String.trim()
    |> String.slice(0, 2000)
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  @impl true
  def handle_event("chat:send", params, socket) do
    sanitized =
      params
      |> Map.get("text", "")
      |> sanitize_text()

    if sanitized == "" do
      {:noreply, assign(socket, chat_form: to_form(%{"text" => ""}), chat_sending?: false)}
    else
      payload = %{
        "from_id" => socket.assigns[:participant_id] || "lv",
        "display_name" => socket.assigns.display_name,
        "text" => sanitized,
        "ts" => System.system_time(:millisecond)
      }

      PhoenixChatWeb.Endpoint.broadcast("room:#{socket.assigns.room_id}", "chat:msg", payload)

      {:noreply, assign(socket, chat_form: to_form(%{"text" => ""}), chat_sending?: false)}
    end
  end
end
