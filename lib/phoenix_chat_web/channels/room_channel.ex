defmodule PhoenixChatWeb.RoomChannel do
  @moduledoc false
  use Phoenix.Channel

  alias PhoenixChatWeb.Presence
  require Logger

  # -- Join --------------------------------------------------------------------

  @impl true
  def join("room:" <> room_id, params, socket) when is_binary(room_id) and is_map(params) do
    with {:ok, display_name} <- validate_display_name(params),
         {:ok, device_info} <- validate_device_info(Map.get(params, "device_info")),
         true <- capacity_ok?("room:" <> room_id) do
      participant_id = Ecto.UUID.generate()

      socket =
        socket
        |> assign(:room_id, room_id)
        |> assign(:participant_id, participant_id)
        |> assign(:display_name, display_name)
        |> assign(:audio_muted, false)
        |> assign(:video_enabled, true)
        |> assign(:screensharing, false)
        |> assign(:device_info, device_info)

      Logger.info("room join",
        room_id: room_id,
        participant_id: participant_id,
        display_name: display_name
      )

      send(self(), :after_join)

      {:ok, %{participant_id: participant_id}, socket}
    else
      false ->
        current_count = Presence.list("room:" <> room_id) |> map_size()
        Logger.warning("room capacity rejection", room_id: room_id, current_count: current_count)
        {:error, %{reason: "error:capacity"}}

      {:error, :invalid_display_name} ->
        {:error, %{reason: "error:invalid_payload"}}

      {:error, :invalid_device_info} ->
        {:error, %{reason: "error:invalid_payload"}}
    end
  end

  def join("room:" <> _room_id, _params, _socket),
    do: {:error, %{reason: "error:invalid_payload"}}

  def join(_topic, _params, _socket), do: {:error, %{reason: "error:invalid_payload"}}

  # -- After join ---------------------------------------------------------------

  @impl true
  def handle_info(:after_join, socket) do
    meta = %{
      display_name: socket.assigns.display_name,
      audio_muted: socket.assigns.audio_muted,
      video_enabled: socket.assigns.video_enabled,
      screensharing: socket.assigns.screensharing,
      device_info: socket.assigns.device_info
    }

    :ok = Presence.track(self(), socket.topic, socket.assigns.participant_id, meta)

    Logger.debug("presence tracked",
      room_id: socket.assigns.room_id,
      participant_id: socket.assigns.participant_id
    )

    push(socket, "presence_state", Presence.list(socket.topic))

    {:noreply, socket}
  end

  # -- Signaling ---------------------------------------------------------------

  @impl true
  def handle_in("signal:offer", %{"to_id" => to, "sdp" => sdp} = _payload, socket)
      when is_binary(to) and is_binary(sdp) do
    payload = %{
      "from_id" => socket.assigns.participant_id,
      "to_id" => to,
      "sdp" => sdp
    }

    Logger.info("signal:offer",
      room_id: socket.assigns.room_id,
      from_id: socket.assigns.participant_id,
      to_id: to
    )

    :telemetry.execute([:phoenix_chat, :signal, :offer], %{}, %{
      room_id: socket.assigns.room_id,
      from_id: socket.assigns.participant_id,
      to_id: to
    })

    broadcast!(socket, "signal:offer", payload)
    {:noreply, socket}
  end

  def handle_in("signal:answer", %{"to_id" => to, "sdp" => sdp} = _payload, socket)
      when is_binary(to) and is_binary(sdp) do
    payload = %{
      "from_id" => socket.assigns.participant_id,
      "to_id" => to,
      "sdp" => sdp
    }

    Logger.info("signal:answer",
      room_id: socket.assigns.room_id,
      from_id: socket.assigns.participant_id,
      to_id: to
    )

    :telemetry.execute([:phoenix_chat, :signal, :answer], %{}, %{
      room_id: socket.assigns.room_id,
      from_id: socket.assigns.participant_id,
      to_id: to
    })

    broadcast!(socket, "signal:answer", payload)
    {:noreply, socket}
  end

  def handle_in("signal:ice", %{"to_id" => to} = payload, socket) when is_binary(to) do
    candidate = Map.get(payload, "candidate")

    if is_binary(candidate) and byte_size(String.trim(candidate)) > 0 do
      filtered =
        payload
        |> Map.take(["candidate", "sdpMid", "sdpMLineIndex"])
        |> Map.put("from_id", socket.assigns.participant_id)
        |> Map.put("to_id", to)

      Logger.info("signal:ice",
        room_id: socket.assigns.room_id,
        from_id: socket.assigns.participant_id,
        to_id: to,
        candidate_present: true
      )

      :telemetry.execute([:phoenix_chat, :signal, :ice], %{}, %{
        room_id: socket.assigns.room_id,
        from_id: socket.assigns.participant_id,
        to_id: to
      })

      broadcast!(socket, "signal:ice", filtered)
      {:noreply, socket}
    else
      {:reply, {:error, %{reason: "error:invalid_payload"}}, socket}
    end
  end

  # -- Media updates -----------------------------------------------------------

  def handle_in("media:update", params, socket) when is_map(params) do
    {san_atom, san_json} = sanitize_media_params(params)

    :ok =
      Presence.update(self(), socket.topic, socket.assigns.participant_id, fn meta ->
        Map.merge(meta, san_atom)
      end)

    Logger.debug("media:update",
      room_id: socket.assigns.room_id,
      from_id: socket.assigns.participant_id,
      audio_muted: Map.get(san_atom, :audio_muted),
      video_enabled: Map.get(san_atom, :video_enabled),
      screensharing: Map.get(san_atom, :screensharing)
    )

    :telemetry.execute([:phoenix_chat, :media, :update], %{}, %{
      room_id: socket.assigns.room_id,
      from_id: socket.assigns.participant_id,
      audio_muted: Map.get(san_atom, :audio_muted),
      video_enabled: Map.get(san_atom, :video_enabled),
      screensharing: Map.get(san_atom, :screensharing)
    })

    broadcast!(
      socket,
      "media:update",
      Map.put(san_json, "from_id", socket.assigns.participant_id)
    )

    {:noreply, socket}
  end

  # -- In-room chat ------------------------------------------------------------

  def handle_in("chat:msg", %{"text" => text}, socket) do
    clean =
      text
      |> to_string()
      |> String.trim()
      |> String.slice(0, 2_000)
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    msg = %{
      "from_id" => socket.assigns.participant_id,
      "display_name" => socket.assigns.display_name,
      "text" => clean,
      "ts" => System.system_time(:millisecond)
    }

    Logger.info("chat:msg",
      room_id: socket.assigns.room_id,
      from_id: socket.assigns.participant_id,
      display_name: socket.assigns.display_name,
      text_length: byte_size(clean)
    )

    :telemetry.execute([:phoenix_chat, :chat, :msg], %{}, %{
      room_id: socket.assigns.room_id,
      from_id: socket.assigns.participant_id,
      bytes: byte_size(clean)
    })

    broadcast!(socket, "chat:msg", msg)
    {:noreply, socket}
  end

  # -- Fallback for invalid payloads ------------------------------------------

  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "error:invalid_payload"}}, socket}
  end

  # -- Helpers -----------------------------------------------------------------

  defp validate_display_name(%{"display_name" => dn}) when is_binary(dn) do
    case String.trim(dn) do
      "" -> {:error, :invalid_display_name}
      val -> {:ok, val}
    end
  end

  defp validate_display_name(_), do: {:error, :invalid_display_name}

  defp validate_device_info(nil), do: {:ok, %{}}
  defp validate_device_info(%{} = m), do: {:ok, m}
  defp validate_device_info(_), do: {:error, :invalid_device_info}

  defp capacity_ok?(topic) do
    Presence.list(topic) |> map_size() < 6
  end

  defp sanitize_media_params(params) do
    bool = fn
      true -> true
      false -> false
      "true" -> true
      "false" -> false
      1 -> true
      0 -> false
      _ -> nil
    end

    acc0 = {%{}, %{}}

    Enum.reduce(["audio_muted", "video_enabled", "screensharing", "device_info"], acc0, fn key,
                                                                                           {a_acc,
                                                                                            j_acc} ->
      case key do
        "device_info" ->
          case Map.get(params, key) do
            %{} = m ->
              {Map.put(a_acc, :device_info, m), Map.put(j_acc, "device_info", m)}

            _ ->
              {a_acc, j_acc}
          end

        _ ->
          case bool.(Map.get(params, key)) do
            nil ->
              {a_acc, j_acc}

            v ->
              atom_key =
                case key do
                  "audio_muted" -> :audio_muted
                  "video_enabled" -> :video_enabled
                  "screensharing" -> :screensharing
                end

              {Map.put(a_acc, atom_key, v), Map.put(j_acc, key, v)}
          end
      end
    end)
  end
end
