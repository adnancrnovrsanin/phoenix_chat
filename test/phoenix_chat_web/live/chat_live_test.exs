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

    test "groups consecutive same-author messages, day divider on first", %{
      conn: conn,
      user: user
    } do
      general = Chat.get_channel_by_slug!("general")
      message_fixture(user, general, %{body: "prva"})
      message_fixture(user, general, %{body: "druga"})
      other = user_fixture()
      message_fixture(other, general, %{body: "treca"})

      {:ok, view, _html} = live(conn, ~p"/c/general")

      assert has_element?(view, ".cds-message-compact", "druga")
      refute has_element?(view, ".cds-message-compact", "prva")
      refute has_element?(view, ".cds-message-compact", "treca")
      assert has_element?(view, ".cds-day-divider")
    end

    test "realtime messages group against the previous one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      view |> form("#composer", message: %{body: "brza jedan"}) |> render_submit()
      view |> form("#composer", message: %{body: "brza dva"}) |> render_submit()

      assert has_element?(view, ".cds-message-compact", "brza dva")
      refute has_element?(view, ".cds-message-compact", "brza jedan")
    end

    test "load older paginates past 50 messages", %{conn: conn, user: user} do
      general = Chat.get_channel_by_slug!("general")

      for i <- 1..55 do
        padded = String.pad_leading(Integer.to_string(i), 3, "0")
        message_fixture(user, general, %{body: "st-#{padded}"})
      end

      {:ok, view, _html} = live(conn, ~p"/c/general")

      refute render(view) =~ "st-005"
      assert render(view) =~ "st-006"
      assert has_element?(view, "#load-older")

      view |> element("#load-older") |> render_click()

      assert render(view) =~ "st-001"
      refute has_element?(view, "#load-older")
    end
  end
end
