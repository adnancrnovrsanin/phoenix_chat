defmodule PhoenixChatWeb.RoomLiveTest do
  use PhoenixChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PhoenixChat.AccountsFixtures
  import PhoenixChat.ChatFixtures

  describe "huddle" do
    setup :register_and_log_in_user

    test "redirects anonymous users to login" do
      conn = Phoenix.ConnTest.build_conn()
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/huddle/general")
    end

    test "renders the huddle stage for members", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/huddle/general")

      for id <-
            ~w(rtc-root video-grid local-video controls-bar btn-mic btn-cam btn-share chat-panel messages chat-form participants) do
        assert has_element?(view, "##{id}")
      end

      assert has_element?(view, ~s{#rtc-root[data-display-name="#{user.username}"]})
      assert has_element?(view, ~s{#rtc-root[data-room-id="general"]})
    end

    test "exposes a valid socket token to the RTC hook", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/huddle/general")

      assert [_full, token] = Regex.run(~r/data-token="([^"]+)"/, render(view))

      assert {:ok, user_id} =
               Phoenix.Token.verify(PhoenixChatWeb.Endpoint, "user socket", token,
                 max_age: 86_400
               )

      assert user_id == user.id
    end

    test "bounces non-members to the app", %{conn: conn} do
      other = user_fixture()
      channel_fixture(other, %{name: "privatna-ekipa"})

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/huddle/privatna-ekipa")
    end

    test "in-huddle chat renders messages", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/huddle/general")

      view |> form("#chat-form", %{text: "test u sobi"}) |> render_submit()
      assert render(view) =~ "test u sobi"
    end
  end
end
