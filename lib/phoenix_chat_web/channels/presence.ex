defmodule PhoenixChatWeb.Presence do
  @moduledoc false

  use Phoenix.Presence,
    otp_app: :phoenix_chat,
    pubsub_server: PhoenixChat.PubSub
end
