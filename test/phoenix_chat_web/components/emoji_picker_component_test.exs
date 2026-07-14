defmodule PhoenixChatWeb.EmojiPickerComponentTest do
  use PhoenixChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defmodule HostLive do
    use PhoenixChatWeb, :live_view

    @impl true
    def mount(_params, _session, socket),
      do: {:ok, Phoenix.Component.assign(socket, :picked, nil)}

    @impl true
    def handle_event("emoji_picked", %{"emoji" => emoji, "target" => target}, socket) do
      {:noreply, Phoenix.Component.assign(socket, :picked, "#{target}:#{emoji}")}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div>
        <div id="picked">{@picked}</div>
        <.live_component
          module={PhoenixChatWeb.EmojiPickerComponent}
          id="emoji-picker"
          target={:reaction}
        />
      </div>
      """
    end
  end

  test "renders a search box and an emoji grid" do
    html =
      render_component(PhoenixChatWeb.EmojiPickerComponent, id: "emoji-picker", target: :reaction)

    assert html =~ ~s(name="q")
    assert html =~ "😀"
  end

  test "searching narrows the grid to matches", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, HostLive)

    html =
      view
      |> form("#emoji-picker-search", %{q: "tada"})
      |> render_change()

    assert html =~ "🎉"
    refute html =~ "😀"
  end

  test "picking an emoji notifies the parent LiveView", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, HostLive)

    view
    |> element(~s(#emoji-picker button[phx-value-emoji="😀"]))
    |> render_click()

    assert has_element?(view, "#picked", "reaction:😀")
  end
end
