defmodule PhoenixChatWeb.PageController do
  use PhoenixChatWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
