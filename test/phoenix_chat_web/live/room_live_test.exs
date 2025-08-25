defmodule PhoenixChatWeb.RoomLiveTest do
  use PhoenixChatWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "redirects to lobby when dn is missing", %{conn: conn} do
    # Can't use ~p inside a match; bind and assert instead
    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/r/roomx")
    assert to == ~p"/"
  end

  test "renders room placeholders and panels with provided dn", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/r/roomx?dn=Alice")
    assert has_element?(view, "#room-title")
    assert has_element?(view, "#display-name")
    assert has_element?(view, "#video-grid")
    assert has_element?(view, "#controls-bar")
    assert has_element?(view, "#chat-panel")
    assert has_element?(view, "#participants")
    assert has_element?(view, "#messages")
    assert has_element?(view, "#chat-form")
  end
end
