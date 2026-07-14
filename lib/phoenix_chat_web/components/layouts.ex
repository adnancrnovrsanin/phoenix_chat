defmodule PhoenixChatWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PhoenixChatWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-dvh flex-col">
      <header class="flex h-16 items-center justify-between px-6">
        <a href="/" class="flex items-center gap-2.5">
          <span class="grid size-7 place-items-center rounded-lg bg-accent text-accent-foreground">
            <.icon name="hero-chat-bubble-left-ellipsis-solid" class="size-4" />
          </span>
          <span class="text-sm font-semibold text-foreground">PhoenixChat</span>
        </a>
        <div class="flex items-center gap-2">
          <div :if={@current_scope} class="flex items-center gap-4 pr-1 text-sm">
            <span class="text-muted">{@current_scope.user.username}</span>
            <.link href={~p"/users/settings"} class="text-foreground hover:text-muted">
              {gettext("Settings")}
            </.link>
            <.link href={~p"/users/log-out"} method="delete" class="text-foreground hover:text-muted">
              {gettext("Log out")}
            </.link>
          </div>
          <.theme_toggle />
        </div>
      </header>

      <main class="flex flex-1 items-start justify-center px-4 py-10 sm:py-16">
        <div class="w-full max-w-md">
          <div class="glass rounded-2xl border border-border bg-surface p-6 text-surface-foreground shadow-[0_14px_28px_-12px_rgba(0,0,0,0.25)] sm:p-8">
            {render_slot(@inner_block)}
          </div>
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
