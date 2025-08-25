defmodule PhoenixChatWeb.LobbyLiveTest do
  use PhoenixChatWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "renders the lobby form and controls", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#lobby-form")
    assert has_element?(view, "#gen-room")
    assert has_element?(view, "#join-room")
  end

  test "submitting the form navigates to the room with dn query", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    _html =
      render_submit(element(view, "#lobby-form"), %{
        "display_name" => "Alice",
        "room_id" => "room123"
      })

    assert_redirect(view, ~p"/r/room123?dn=Alice")
  end
end
