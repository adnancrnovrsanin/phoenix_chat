defmodule PhoenixChatWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", PhoenixChatWeb.RoomChannel

  # Tokens are minted per page render (RoomLive); a day is plenty.
  @token_max_age 86_400

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Phoenix.Token.verify(PhoenixChatWeb.Endpoint, "user socket", token,
           max_age: @token_max_age
         ) do
      {:ok, user_id} -> {:ok, assign(socket, :user_id, user_id)}
      {:error, _reason} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
