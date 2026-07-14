defmodule PhoenixChatWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS v4, a utility-first CSS
  framework, driven by the "Glass" design system. Rather than branching on
  light/dark, components use semantic utilities (`bg-surface`, `text-muted`,
  `border-separator`, `bg-accent`, `text-danger`, `field-*`…) whose values
  are defined once in `assets/css/app.css` and flip automatically via the
  `[data-theme]` attribute set by the theme toggle. See `DESIGN.md` for the
  full token reference. Useful references:

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: PhoenixChatWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "group fixed top-4 right-4 z-50 flex w-80 items-start gap-3 sm:w-96",
        "glass rounded-2xl border border-border bg-overlay/90 p-3 text-overlay-foreground",
        "shadow-[0_14px_28px_-8px_rgba(0,0,0,0.25)] cursor-pointer"
      ]}
      {@rest}
    >
      <.icon
        :if={@kind == :info}
        name="hero-information-circle"
        class="size-5 shrink-0 text-foreground"
      />
      <.icon
        :if={@kind == :error}
        name="hero-exclamation-circle"
        class="size-5 shrink-0 text-danger"
      />
      <div class="min-w-0 flex-1">
        <p :if={@title} class="text-sm font-semibold">{@title}</p>
        <p class="text-sm text-muted">{msg}</p>
      </div>
      <.icon
        name="hero-x-mark"
        class="size-5 shrink-0 text-muted opacity-60 group-hover:opacity-100"
      />
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any, default: nil
  attr :variant, :string, default: "primary", values: ~w(primary secondary outline ghost danger)
  slot :inner_block, required: true

  @button_base "inline-flex items-center justify-center gap-2 h-10 px-4 rounded-xl border text-sm font-medium select-none transition-colors cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-focus/60 focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:opacity-50 disabled:pointer-events-none"

  @button_variants %{
    "primary" => "border-transparent bg-accent text-accent-foreground hover:bg-accent-hover",
    "secondary" => "border-transparent bg-default text-default-foreground hover:bg-default-hover",
    "outline" => "border-border text-foreground hover:bg-surface-hover",
    "ghost" => "border-transparent text-foreground hover:bg-default",
    "danger" => "border-transparent bg-danger text-danger-foreground hover:bg-danger-hover"
  }

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :computed_class, [
        @button_base,
        Map.fetch!(@button_variants, assigns.variant),
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@computed_class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@computed_class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an icon-only button. Always wrap the action in a tooltip via `title`
  for discoverability and accessibility.
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def icon_button(assigns) do
    ~H"""
    <button
      class={[
        "inline-flex size-9 items-center justify-center rounded-lg text-muted",
        "transition-colors cursor-pointer hover:bg-default hover:text-foreground",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-focus/60",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a light/dark theme toggle. Requires the `ThemeToggle` JS hook.
  """
  attr :id, :string, default: "theme-toggle"
  attr :class, :any, default: nil

  def theme_toggle(assigns) do
    ~H"""
    <.icon_button
      id={@id}
      phx-hook="ThemeToggle"
      class={@class}
      title={gettext("Toggle theme")}
      aria-label={gettext("Toggle theme")}
    >
      <.icon name="hero-moon" class="size-5 dark:hidden" />
      <.icon name="hero-sun" class="hidden size-5 dark:block" />
    </.icon_button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  # Shared field styling. Fields use the neutral field tokens so they read
  # correctly against both page and elevated (card/modal) surfaces.
  @field_base "w-full rounded-xl bg-field-background text-field-foreground text-sm placeholder:text-field-placeholder border border-field-border transition-colors focus:outline-none focus:border-field-border-focus focus:ring-2 focus:ring-focus/20"
  @field_error "border-danger focus:border-danger focus:ring-danger/20"

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-3">
      <label class="flex items-center gap-2 text-sm text-foreground">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "size-4 rounded accent-[var(--accent)]"}
          {@rest}
        />{@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    assigns = assign(assigns, :field_class, field_class(assigns, "h-10 px-3"))

    ~H"""
    <div class="mb-3">
      <label :if={@label} for={@id} class="mb-1.5 block text-sm font-medium text-foreground">
        {@label}
      </label>
      <select
        id={@id}
        name={@name}
        class={@field_class}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    assigns = assign(assigns, :field_class, field_class(assigns, "min-h-24 px-3 py-2"))

    ~H"""
    <div class="mb-3">
      <label :if={@label} for={@id} class="mb-1.5 block text-sm font-medium text-foreground">
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={@field_class}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    assigns = assign(assigns, :field_class, field_class(assigns, "h-10 px-3"))

    ~H"""
    <div class="mb-3">
      <label :if={@label} for={@id} class="mb-1.5 block text-sm font-medium text-foreground">
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={@field_class}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Builds the class list for a field, honoring a caller-provided `:class`
  # override and appending an error style when the field has errors.
  defp field_class(assigns, size) do
    assigns[:class] || [@field_base, size, assigns.errors != [] && @field_error]
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex items-center gap-1.5 text-sm text-danger">
      <.icon name="hero-exclamation-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-xl font-semibold tracking-tight text-foreground">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-1 text-sm text-muted">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="w-full text-sm">
      <thead>
        <tr class="border-b border-separator text-left text-muted">
          <th :for={col <- @col} class="px-3 py-2 font-medium">{col[:label]}</th>
          <th :if={@action != []} class="px-3 py-2">
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class="border-b border-separator/60 text-foreground hover:bg-surface-hover"
        >
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={["px-3 py-2 tabular-nums", @row_click && "cursor-pointer"]}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 px-3 py-2 font-medium">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="divide-y divide-separator">
      <li :for={item <- @item} class="flex flex-col gap-0.5 py-3">
        <div class="text-sm font-semibold text-foreground">{item.title}</div>
        <div class="text-sm text-muted">{render_slot(item)}</div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(PhoenixChatWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(PhoenixChatWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
