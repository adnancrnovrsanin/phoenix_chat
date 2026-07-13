defmodule PhoenixChatWeb.ChatLiveTest do
  use PhoenixChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PhoenixChat.AccountsFixtures
  import PhoenixChat.ChatFixtures

  alias PhoenixChat.Chat

  test "redirects anonymous visitors to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  describe "channel view" do
    setup :register_and_log_in_user

    test "/ patches to #general", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert_patch(view, ~p"/c/general")
      assert has_element?(view, ".cds-channel-name", "#general")
    end

    test "sends a message and renders it", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      view
      |> form("#composer", message: %{body: "prva poruka"})
      |> render_submit()

      assert has_element?(view, "#message-list", "prva poruka")
      assert has_element?(view, "#message-list", user.username)
    end

    test "rejects an empty message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      html =
        view
        |> form("#composer", message: %{body: "   "})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "receives another member's message in real time", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      other = user_fixture()
      general = Chat.get_channel_by_slug!("general")
      {:ok, _} = Chat.send_message(other, general, %{body: "zdravo iz drugog procesa"})

      assert render(view) =~ "zdravo iz drugog procesa"
    end

    test "patching between channels loads their messages", %{conn: conn, user: user} do
      channel = channel_fixture(user, %{name: "drugi"})
      message_fixture(user, channel, %{body: "u drugom kanalu"})

      {:ok, view, _html} = live(conn, ~p"/c/general")
      refute render(view) =~ "u drugom kanalu"

      view |> element(~s{a[href="/c/drugi"]}) |> render_click()
      assert_patch(view, ~p"/c/drugi")
      assert render(view) =~ "u drugom kanalu"
    end

    test "sidebar shows initial unread counts", %{conn: conn, user: user} do
      other = user_fixture()
      channel = channel_fixture(other, %{name: "vruce"})
      {:ok, _} = Chat.join_channel(user, channel)
      message_fixture(other, channel, %{body: "nepročitano"})

      {:ok, view, _html} = live(conn, ~p"/c/general")
      assert has_element?(view, ~s{a[href="/c/vruce"] .cds-unread-badge}, "1")
    end
  end
end
