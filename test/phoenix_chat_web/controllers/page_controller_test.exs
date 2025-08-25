defmodule PhoenixChatWeb.PageControllerTest do
  use PhoenixChatWeb.ConnCase

  test "GET / renders lobby", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ ~s(id="lobby-form")
  end
end
