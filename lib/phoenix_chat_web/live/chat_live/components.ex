defmodule PhoenixChatWeb.ChatComponents do
  @moduledoc "Function components for the chat shell."
  use PhoenixChatWeb, :html

  # Sidebar nav item classes. Active items get an elevated surface + subtle
  # shadow; inactive items stay neutral and only shade on hover.
  defp item_class(active?) do
    [
      "group flex h-9 items-center gap-2 rounded-lg px-2 text-sm",
      (active? && "bg-surface text-foreground font-medium shadow-sm") ||
        "text-muted hover:bg-default hover:text-foreground"
    ]
  end

  attr :row, :map, required: true, doc: "%{channel: Channel, unread: integer}"
  attr :active_id, :any, default: nil

  def sidebar_item(assigns) do
    active? = assigns.active_id == assigns.row.channel.id
    assigns = assign(assigns, :item_class, item_class(active?))

    ~H"""
    <.link patch={~p"/c/#{@row.channel.slug}"} class={@item_class}>
      <span class="text-muted" aria-hidden="true">#</span>
      <span class="min-w-0 flex-1 truncate">{@row.channel.name}</span>
      <span :if={@row.unread > 0} class={unread_badge()}>{@row.unread}</span>
    </.link>
    """
  end

  attr :row, :map, required: true, doc: "%{channel:, other_user:, unread:}"
  attr :active_id, :any, default: nil
  attr :online, :any, required: true, doc: "MapSet of online user ids (strings)"

  def dm_item(assigns) do
    active? = assigns.active_id == assigns.row.channel.id

    assigns =
      assigns
      |> assign(:item_class, item_class(active?))
      |> assign(:online?, MapSet.member?(assigns.online, to_string(assigns.row.other_user.id)))

    ~H"""
    <.link patch={~p"/dm/#{@row.other_user.username}"} class={@item_class}>
      <span
        class={[
          "size-2 flex-none rounded-full",
          (@online? && "cds-presence-dot-online bg-success") || "border border-muted"
        ]}
        aria-hidden="true"
      ></span>
      <span class="min-w-0 flex-1 truncate">{@row.other_user.username}</span>
      <span :if={@row.unread > 0} class={unread_badge()}>{@row.unread}</span>
    </.link>
    """
  end

  defp unread_badge do
    "cds-unread-badge ml-auto inline-flex min-w-5 items-center justify-center rounded-full bg-accent px-1.5 text-xs font-medium text-accent-foreground tabular-nums"
  end

  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :palette_for, :any, default: nil
  attr :me_id, :any, required: true
  attr :editing_id, :any, default: nil
  attr :edit_form, :any, default: nil
  attr :unread_boundary_id, :any, default: nil

  def message_entry(assigns) do
    ~H"""
    <div id={@id}>
      <div
        :if={@unread_boundary_id == @entry.id}
        id="unread-divider"
        class="cds-unread-divider flex items-center gap-3 px-2 py-1.5"
      >
        <span class="h-px flex-1 bg-danger"></span>
        <span class="text-xs font-semibold uppercase tracking-wide text-danger">
          {gettext("New")}
        </span>
        <span class="h-px flex-1 bg-danger"></span>
      </div>
      <div :if={@entry.day_break?} class="cds-day-divider flex items-center gap-3 px-2 py-2">
        <span class="h-px flex-1 bg-separator"></span>
        <span class="text-xs text-muted tabular-nums">{format_date(@entry.inserted_at)}</span>
        <span class="h-px flex-1 bg-separator"></span>
      </div>
      <div
        data-msg
        class={[
          "group relative flex gap-3 rounded-lg px-2 hover:bg-surface-hover",
          (@entry.compact? && "cds-message-compact py-0.5") || "py-1"
        ]}
      >
        <%= if @entry.compact? do %>
          <span class="w-8 flex-none pt-0.5 text-right text-xs text-muted opacity-0 tabular-nums group-hover:opacity-100">
            {format_time(@entry.inserted_at)}
          </span>
        <% else %>
          <.avatar username={@entry.username} />
        <% end %>
        <div class="min-w-0 flex-1">
          <div :if={!@entry.compact?} class="flex items-baseline gap-2">
            <span class="text-sm font-semibold">{@entry.username}</span>
            <span class="text-xs text-muted tabular-nums">{format_time(@entry.inserted_at)}</span>
          </div>

          <%= cond do %>
            <% @entry.deleted? -> %>
              <p class="cds-tombstone text-sm italic text-muted">
                {gettext("This message was deleted")}
              </p>
            <% @editing_id == @entry.id -> %>
              <.form
                for={@edit_form}
                id={"edit-message-#{@entry.id}"}
                phx-submit="save_edit"
                class="mt-0.5"
              >
                <div class="rounded-xl border border-field-border bg-field-background focus-within:border-field-border-focus focus-within:ring-2 focus-within:ring-focus/20">
                  <textarea
                    id={"edit-input-#{@entry.id}"}
                    name={@edit_form[:body].name}
                    rows="1"
                    class="block max-h-40 w-full resize-none bg-transparent px-3 py-2 text-sm text-field-foreground focus:outline-none"
                  >{Phoenix.HTML.Form.normalize_value("textarea", @edit_form[:body].value)}</textarea>
                </div>
                <div class="mt-1 flex items-center gap-2">
                  <.button type="submit" class="h-7 px-2.5 text-xs">{gettext("Save")}</.button>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    class="inline-flex h-7 cursor-pointer items-center rounded-lg px-2.5 text-xs text-muted hover:bg-surface-hover hover:text-foreground"
                  >
                    {gettext("Cancel")}
                  </button>
                  <p
                    :for={msg <- Enum.map(@edit_form[:body].errors, &translate_error/1)}
                    class="text-xs text-danger"
                  >
                    {msg}
                  </p>
                </div>
              </.form>
            <% true -> %>
              <div data-msg-body class="whitespace-pre-wrap break-words text-sm text-foreground">
                {PhoenixChat.Markdown.render(@entry.body)}
              </div>
              <span :if={@entry.edited?} class="cds-edited-marker text-xs italic text-muted">
                {gettext("(edited)")}
              </span>
          <% end %>

          <div
            :if={@entry.reactions != [] and not @entry.deleted? and @editing_id != @entry.id}
            class="mt-1 flex flex-wrap gap-1"
          >
            <button
              :for={r <- @entry.reactions}
              phx-click="toggle_reaction"
              phx-value-message-id={@entry.id}
              phx-value-emoji={r.emoji}
              class={[
                "cds-reaction-chip inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs cursor-pointer",
                (r.mine &&
                   "cds-reaction-chip-mine border-accent bg-accent-soft text-accent-soft-foreground") ||
                  "border-border text-muted hover:border-border-secondary"
              ]}
            >
              <span>{r.emoji}</span>
              <span class="font-medium tabular-nums">{r.count}</span>
            </button>
          </div>

          <button
            :if={@entry.reply_count > 0 and not @entry.deleted? and @editing_id != @entry.id}
            phx-click="open_thread"
            phx-value-message-id={@entry.id}
            class="cds-thread-affordance mt-1 inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-xs font-medium text-accent hover:bg-surface-hover"
          >
            <.icon name="hero-chat-bubble-left-right" class="size-3.5" />
            <span class="cds-thread-count tabular-nums">{@entry.reply_count}</span>
            <span>{ngettext("reply", "replies", @entry.reply_count)}</span>
            <span :if={@entry.last_reply_at} class="text-muted">
              {gettext("· last reply %{time}", time: format_time(@entry.last_reply_at))}
            </span>
          </button>
        </div>

        <div
          :if={not @entry.deleted? and @editing_id != @entry.id}
          class="absolute -top-3.5 right-2 flex items-center gap-0.5 rounded-lg border border-border bg-overlay p-0.5 opacity-0 shadow-sm transition-opacity focus-within:opacity-100 group-hover:opacity-100"
        >
          <button
            phx-click="open_palette"
            phx-value-message-id={@entry.id}
            class="cds-reaction-add inline-flex size-7 cursor-pointer items-center justify-center rounded-md text-muted hover:bg-surface-hover hover:text-foreground"
            aria-label={gettext("Add reaction")}
            title={gettext("Add reaction")}
          >
            <.icon name="hero-face-smile" class="size-4" />
          </button>
          <button
            :if={@entry.user_id == @me_id}
            phx-click="edit_message"
            phx-value-message-id={@entry.id}
            class="cds-edit-message inline-flex size-7 cursor-pointer items-center justify-center rounded-md text-muted hover:bg-surface-hover hover:text-foreground"
            aria-label={gettext("Edit message")}
            title={gettext("Edit message")}
          >
            <.icon name="hero-pencil-square" class="size-4" />
          </button>
          <button
            :if={@entry.user_id == @me_id}
            phx-click="delete_message"
            phx-value-message-id={@entry.id}
            data-confirm={gettext("Delete this message?")}
            class="cds-delete-message inline-flex size-7 cursor-pointer items-center justify-center rounded-md text-muted hover:bg-surface-hover hover:text-danger"
            aria-label={gettext("Delete message")}
            title={gettext("Delete message")}
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
          <button
            type="button"
            data-copy
            class="inline-flex size-7 cursor-pointer items-center justify-center rounded-md text-muted hover:bg-surface-hover hover:text-foreground"
            aria-label={gettext("Copy message")}
            title={gettext("Copy message")}
          >
            <.icon name="hero-clipboard-document" class="size-4" />
          </button>
        </div>

        <div
          :if={@palette_for == @entry.id and not @entry.deleted?}
          class="glass absolute right-2 top-5 z-10 flex gap-0.5 rounded-xl border border-border bg-overlay p-1 shadow-lg"
        >
          <button
            :for={emoji <- PhoenixChat.Chat.reaction_palette()}
            phx-click="pick_reaction"
            phx-value-message-id={@entry.id}
            phx-value-emoji={emoji}
            class="cds-palette-item cursor-pointer rounded-lg px-1.5 py-1 text-base hover:bg-surface-hover"
          >
            {emoji}
          </button>
          <button
            type="button"
            phx-click="open_reaction_picker"
            phx-value-message-id={@entry.id}
            class="cds-emoji-more inline-flex size-8 cursor-pointer items-center justify-center rounded-lg text-muted hover:bg-surface-hover hover:text-foreground"
            aria-label={gettext("More emoji")}
            title={gettext("More emoji")}
          >
            <.icon name="hero-plus" class="size-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :username, :string, required: true

  def avatar(assigns) do
    ~H"""
    <span class="inline-flex size-8 flex-none items-center justify-center rounded-full bg-surface-secondary text-xs font-medium text-foreground">
      {@username |> String.slice(0, 2) |> String.upcase()}
    </span>
    """
  end

  attr :title, :string, required: true
  attr :topic, :string, default: nil
  attr :other, :any, default: nil, doc: "the other user for a DM, or nil for a channel"
  attr :online, :any, default: nil, doc: "MapSet of online user ids (strings)"
  slot :actions

  def channel_header(assigns) do
    ~H"""
    <header class="flex h-14 flex-none items-center gap-3 border-b border-border px-4">
      <.icon_button
        id="mobile-back-button"
        type="button"
        phx-click="open_mobile_sidebar"
        class="flex-none md:hidden"
        title={gettext("Back to conversations")}
        aria-label={gettext("Back to conversations")}
      >
        <.icon name="hero-arrow-left" class="size-5" />
      </.icon_button>
      <div :if={@other} class="relative flex-none">
        <.avatar username={@other.username} />
        <span
          class={[
            "absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full border-2 border-background",
            (online?(@online, @other) && "cds-presence-dot-online bg-success") || "bg-muted"
          ]}
          aria-hidden="true"
        ></span>
      </div>
      <div class="min-w-0">
        <div class="flex items-baseline gap-2">
          <span class="cds-channel-name font-semibold">{@title}</span>
          <span :if={@topic && !@other} class="min-w-0 truncate text-sm text-muted">{@topic}</span>
        </div>
        <div :if={@other} class="text-xs leading-tight text-muted">
          {(online?(@online, @other) && gettext("Active now")) || gettext("Offline")}
        </div>
      </div>
      <div class="ml-auto flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  attr :active, :map, required: true
  attr :other, :any, default: nil

  @doc "Intro shown at the top of an empty conversation."
  def conversation_intro(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-3 px-4 py-12 text-center">
      <%= if @other do %>
        <span class="inline-flex size-16 items-center justify-center rounded-full bg-surface-secondary text-xl font-medium text-foreground">
          {@other.username |> String.slice(0, 2) |> String.upcase()}
        </span>
        <div class="text-lg font-semibold">{"@" <> @other.username}</div>
        <p class="max-w-sm text-sm text-muted">
          {gettext(
            "This is the beginning of your direct message history with @%{name}.",
            name: @other.username
          )}
        </p>
      <% else %>
        <span class="inline-flex size-16 items-center justify-center rounded-full bg-surface-secondary text-2xl text-muted">
          #
        </span>
        <div class="text-lg font-semibold">{"#" <> @active.name}</div>
        <p :if={@active.topic} class="max-w-sm text-sm text-foreground">{@active.topic}</p>
        <p class="max-w-sm text-sm text-muted">
          {gettext("This is the start of the #%{name} channel.", name: @active.name)}
        </p>
      <% end %>
    </div>
    """
  end

  attr :users, :list, required: true, doc: "usernames currently typing"

  @doc "Ephemeral 'X is typing…' line rendered beneath the message list."
  def typing_indicator(assigns) do
    ~H"""
    <div
      :if={@users != []}
      class="cds-typing mx-auto max-w-3xl px-4 pb-1 text-xs italic text-muted"
      aria-live="polite"
    >
      {typing_text(@users)}
    </div>
    """
  end

  defp typing_text([user]), do: gettext("%{user} is typing…", user: user)

  defp typing_text([first, second]),
    do: gettext("%{first} and %{second} are typing…", first: first, second: second)

  defp typing_text(_users), do: gettext("Several people are typing…")

  defp online?(nil, _user), do: false
  defp online?(online, user), do: MapSet.member?(online, to_string(user.id))

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, required: true
  attr :on_cancel, :string, required: true, doc: "event name pushed on close"
  slot :inner_block, required: true

  def cds_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      id={@id}
      class="fixed inset-0 z-50 flex items-start justify-center bg-black/40 px-4 pt-24 backdrop-blur-sm"
    >
      <div
        class="glass w-full max-w-md overflow-hidden rounded-2xl border border-border bg-overlay text-overlay-foreground shadow-2xl"
        phx-click-away={JS.push(@on_cancel)}
      >
        <div class="flex items-center justify-between gap-3 border-b border-border px-4 py-3">
          <h2 class="text-base font-semibold">{@title}</h2>
          <.icon_button
            phx-click={@on_cancel}
            title={gettext("Close")}
            aria-label={gettext("Close")}
          >
            <.icon name="hero-x-mark" class="size-5" />
          </.icon_button>
        </div>
        <div class="max-h-[60vh] space-y-1 overflow-y-auto p-3">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  attr :parent, :map, required: true, doc: "the %Message{} the thread is rooted at"
  attr :replies, :any, required: true, doc: "the :thread_messages stream"
  attr :form, :map, required: true, doc: "the thread reply form (as: :reply)"
  attr :title, :string, required: true, doc: "the conversation title (# channel or @ dm)"

  def thread_panel(assigns) do
    ~H"""
    <aside id="thread-panel" class="flex w-full flex-none flex-col border-l border-border md:w-96">
      <header class="flex h-14 flex-none items-center justify-between border-b border-border px-4">
        <div class="min-w-0">
          <div class="text-sm font-semibold">{gettext("Thread")}</div>
          <div class="truncate text-xs text-muted">{@title}</div>
        </div>
        <.icon_button
          id="close-thread"
          phx-click="close_thread"
          title={gettext("Close thread")}
          aria-label={gettext("Close thread")}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </.icon_button>
      </header>

      <div class="flex-1 overflow-y-auto px-2 py-4">
        <div class="mx-auto max-w-3xl">
          <div class="flex gap-3 rounded-lg px-2 py-1">
            <.avatar username={@parent.user.username} />
            <div class="min-w-0 flex-1">
              <div class="flex items-baseline gap-2">
                <span class="text-sm font-semibold">{@parent.user.username}</span>
                <span class="text-xs text-muted tabular-nums">{format_time(@parent.inserted_at)}</span>
              </div>
              <div class="whitespace-pre-wrap break-words text-sm text-foreground">
                {PhoenixChat.Markdown.render(@parent.body)}
              </div>
            </div>
          </div>

          <div :if={@parent.reply_count > 0} class="my-3 flex items-center gap-3 px-2">
            <span class="text-xs text-muted">
              {ngettext("%{count} reply", "%{count} replies", @parent.reply_count)}
            </span>
            <span class="h-px flex-1 bg-separator"></span>
          </div>

          <div id="thread-stream" phx-update="stream" class="space-y-2">
            <div
              :for={{dom_id, entry} <- @replies}
              id={dom_id}
              class="flex gap-3 rounded-lg px-2 py-1"
            >
              <.avatar username={entry.username} />
              <div class="min-w-0 flex-1">
                <div class="flex items-baseline gap-2">
                  <span class="text-sm font-semibold">{entry.username}</span>
                  <span class="text-xs text-muted tabular-nums">{format_time(entry.inserted_at)}</span>
                </div>
                <div class="whitespace-pre-wrap break-words text-sm text-foreground">
                  {PhoenixChat.Markdown.render(entry.body)}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="flex-none px-4 pb-4 pt-2">
        <.form
          for={@form}
          id="thread-composer"
          phx-submit="send_thread_reply"
          class="mx-auto max-w-3xl"
        >
          <div class="rounded-2xl border border-field-border bg-field-background transition-colors focus-within:border-field-border-focus focus-within:ring-2 focus-within:ring-focus/20">
            <label for="thread-composer-input" class="sr-only">{gettext("Reply in thread")}</label>
            <textarea
              id="thread-composer-input"
              name={@form[:body].name}
              rows="1"
              class="block max-h-40 w-full resize-none bg-transparent px-3.5 pb-1.5 pt-3 text-sm text-field-foreground placeholder:text-field-placeholder focus:outline-none"
              placeholder={gettext("Reply…")}
              phx-hook="ComposerKeys"
              data-clear-event="clear-thread-composer"
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>

            <div class="flex items-center justify-between gap-2 px-3 pb-2">
              <label class="flex items-center gap-2 text-xs text-muted">
                <input type="hidden" name={@form[:also_sent_to_channel].name} value="false" />
                <input
                  type="checkbox"
                  name={@form[:also_sent_to_channel].name}
                  value="true"
                  checked={
                    Phoenix.HTML.Form.normalize_value("checkbox", @form[:also_sent_to_channel].value)
                  }
                  class="size-4 rounded accent-[var(--accent)]"
                />{gettext("Also send to channel")}
              </label>
              <button
                type="submit"
                class="inline-flex size-8 cursor-pointer items-center justify-center rounded-lg bg-accent text-accent-foreground transition-colors hover:bg-accent-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-focus/60"
                aria-label={gettext("Send reply")}
              >
                <.icon name="hero-paper-airplane-solid" class="size-4" />
              </button>
            </div>
          </div>
        </.form>
      </div>
    </aside>
    """
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y.")
end
