defmodule PhoenixChatWeb.RoomChannelTest do
  use PhoenixChatWeb.ChannelCase, async: true

  @moduletag capture_log: true

  import PhoenixChat.AccountsFixtures
  import PhoenixChat.ChatFixtures

  alias PhoenixChatWeb.UserSocket

  defp token_for(user) do
    Phoenix.Token.sign(PhoenixChatWeb.Endpoint, "user socket", user.id)
  end

  describe "UserSocket.connect/3" do
    test "refuses connections without a token" do
      assert :error = connect(UserSocket, %{})
    end

    test "refuses connections with an invalid token" do
      assert :error = connect(UserSocket, %{"token" => "garbage"})
    end

    test "connects with a valid token and assigns the user id" do
      user = user_fixture()
      assert {:ok, socket} = connect(UserSocket, %{"token" => token_for(user)})
      assert socket.assigns.user_id == user.id
    end
  end

  describe "RoomChannel.join/3" do
    test "members join their channel's huddle with server-derived display name" do
      user = user_fixture()
      channel = channel_fixture(user)
      {:ok, socket} = connect(UserSocket, %{"token" => token_for(user)})

      assert {:ok, %{participant_id: participant_id}, socket} =
               subscribe_and_join(socket, "room:#{channel.slug}", %{})

      assert is_binary(participant_id)
      assert socket.assigns.display_name == user.username
      assert socket.assigns.room_id == channel.slug
    end

    test "non-members are rejected" do
      owner = user_fixture()
      channel = channel_fixture(owner)
      stranger = user_fixture()
      {:ok, socket} = connect(UserSocket, %{"token" => token_for(stranger)})

      assert {:error, %{reason: "error:unauthorized"}} =
               subscribe_and_join(socket, "room:#{channel.slug}", %{})
    end

    test "unknown room slugs are rejected" do
      user = user_fixture()
      {:ok, socket} = connect(UserSocket, %{"token" => token_for(user)})

      assert {:error, %{reason: "error:unauthorized"}} =
               subscribe_and_join(socket, "room:nema-takvog-kanala", %{})
    end

    test "a client-supplied display_name cannot spoof identity", %{} do
      user = user_fixture()
      channel = channel_fixture(user)
      {:ok, socket} = connect(UserSocket, %{"token" => token_for(user)})

      assert {:ok, _reply, socket} =
               subscribe_and_join(socket, "room:#{channel.slug}", %{
                 "display_name" => "Lazni Admin"
               })

      assert socket.assigns.display_name == user.username
    end
  end
end
