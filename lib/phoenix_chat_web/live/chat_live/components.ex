defmodule PhoenixChatWeb.ChatComponents do
  @moduledoc "Function components for the chat shell."
  use PhoenixChatWeb, :html

  attr :row, :map, required: true, doc: "%{channel: Channel, unread: integer}"
  attr :active_id, :any, default: nil

  def sidebar_item(assigns) do
    ~H"""
    <.link
      patch={~p"/c/#{@row.channel.slug}"}
      class={[
        "cds-sidebar-item",
        @active_id == @row.channel.id && "cds-sidebar-item-active"
      ]}
    >
      <span class="cds-sidebar-hash" aria-hidden="true">#</span>
      <span class="truncate">{@row.channel.name}</span>
      <span :if={@row.unread > 0} class="cds-unread-badge">{@row.unread}</span>
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :entry, :map, required: true

  def message_entry(assigns) do
    ~H"""
    <div id={@id} class="cds-message-wrap">
      <div :if={@entry.day_break?} class="cds-day-divider">
        <span class="cds-day-divider-label">{format_date(@entry.inserted_at)}</span>
      </div>
      <div class={["cds-message", @entry.compact? && "cds-message-compact"]}>
        <%= if @entry.compact? do %>
          <span class="cds-message-gutter">{format_time(@entry.inserted_at)}</span>
        <% else %>
          <.avatar username={@entry.username} />
        <% end %>
        <div class="min-w-0 flex-1">
          <div :if={!@entry.compact?} class="cds-message-meta">
            <span class="cds-message-author">{@entry.username}</span>
            <span class="cds-message-time">{format_time(@entry.inserted_at)}</span>
          </div>
          <p class="cds-message-body">{@entry.body}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :username, :string, required: true

  def avatar(assigns) do
    ~H"""
    <span class="cds-avatar" aria-hidden="true">
      {@username |> String.slice(0, 2) |> String.upcase()}
    </span>
    """
  end

  attr :title, :string, required: true
  attr :topic, :string, default: nil
  slot :actions

  def channel_header(assigns) do
    ~H"""
    <header class="cds-channel-header">
      <span class="cds-channel-name">{@title}</span>
      <span :if={@topic} class="cds-channel-topic">{@topic}</span>
      <div class="ml-auto flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y.")
end
