defmodule PhoenixChatWeb.LobbyLive do
  use PhoenixChatWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"display_name" => "", "room_id" => ""})
    {:ok, assign(socket, form: form, page_title: "Lobby")}
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, form: to_form(params))}
  end

  @impl true
  def handle_event("generate", _params, socket) do
    params =
      socket.assigns.form.params
      |> Map.put("room_id", Ecto.UUID.generate())

    {:noreply, assign(socket, form: to_form(params))}
  end

  @impl true
  def handle_event("join", params, socket) do
    display_name =
      params["display_name"]
      |> to_string()
      |> String.trim()

    room_id =
      params["room_id"]
      |> to_string()
      |> String.trim()

    if display_name == "" do
      {:noreply, assign(socket, form: to_form(params))}
    else
      room_id = if room_id == "", do: Ecto.UUID.generate(), else: room_id
      {:noreply, push_navigate(socket, to: ~p"/r/#{room_id}?dn=#{URI.encode(display_name)}")}
    end
  end
end
