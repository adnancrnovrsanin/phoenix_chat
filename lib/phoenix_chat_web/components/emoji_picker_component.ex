defmodule PhoenixChatWeb.EmojiPickerComponent do
  @moduledoc """
  Searchable, categorized emoji picker.

  Reused by both the reaction affordance (`target: :reaction`) and the composer
  (`target: :composer`). The search box and category tabs are handled inside the
  component (`phx-target={@myself}`); picking an emoji fires the parent event
  `"emoji_picked"` with `%{"emoji" => char, "target" => target, "message-id" => id}`
  so the enclosing LiveView decides what to do with it.

  ## Assigns

    * `:id` (required) — DOM id for the component.
    * `:target` (required) — `:reaction` or `:composer`.
    * `:message_id` (optional) — message the reaction belongs to; passed through
      to the parent event.
  """
  use PhoenixChatWeb, :live_component

  alias PhoenixChat.Emoji

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:message_id, fn -> nil end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:category, fn -> List.first(Emoji.categories()) end)
      |> assign(:categories, Emoji.categories())

    {:ok, assign_results(socket)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> assign_results()}
  end

  def handle_event("select_category", %{"category" => category}, socket) do
    {:noreply, socket |> assign(category: category, query: "") |> assign_results()}
  end

  # Blank query → the active category; otherwise a name+keyword search.
  defp assign_results(socket) do
    %{query: query, category: category} = socket.assigns

    results =
      case String.trim(query) do
        "" -> Enum.filter(Emoji.all(), &(&1.category == category))
        _ -> Emoji.search(query)
      end

    assign(socket, :results, results)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex w-72 flex-col gap-2">
      <form id={"#{@id}-search"} phx-change="search" phx-target={@myself} autocomplete="off">
        <div class="flex items-center gap-2 rounded-lg border border-field-border bg-field-background px-2.5">
          <.icon name="hero-magnifying-glass" class="size-4 text-muted" />
          <input
            type="text"
            name="q"
            value={@query}
            phx-debounce="150"
            placeholder={gettext("Search emoji")}
            class="h-9 w-full bg-transparent text-sm text-field-foreground placeholder:text-field-placeholder focus:outline-none"
          />
        </div>
      </form>

      <div class="flex flex-wrap gap-1" role="tablist" aria-label={gettext("Emoji categories")}>
        <button
          :for={category <- @categories}
          type="button"
          phx-click="select_category"
          phx-value-category={category}
          phx-target={@myself}
          title={category}
          aria-label={category}
          class={[
            "cursor-pointer rounded-md px-2 py-1 text-xs",
            ((@query == "" and @category == category) &&
               "bg-accent-soft text-accent-soft-foreground") ||
              "text-muted hover:bg-surface-hover hover:text-foreground"
          ]}
        >
          {category}
        </button>
      </div>

      <div class="grid max-h-56 grid-cols-8 gap-0.5 overflow-y-auto">
        <button
          :for={emoji <- @results}
          type="button"
          phx-click="emoji_picked"
          phx-value-emoji={emoji.char}
          phx-value-target={@target}
          phx-value-message-id={@message_id}
          title={emoji.name}
          aria-label={emoji.name}
          class="cursor-pointer rounded-md p-1 text-lg leading-none hover:bg-surface-hover"
        >
          {emoji.char}
        </button>
      </div>

      <p :if={@results == []} class="px-1 py-4 text-center text-sm text-muted">
        {gettext("No emoji found")}
      </p>
    </div>
    """
  end
end
