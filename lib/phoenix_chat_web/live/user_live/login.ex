defmodule PhoenixChatWeb.UserLive.Login do
  use PhoenixChatWeb, :live_view

  alias PhoenixChat.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="text-center">
          <.header>
            {gettext("Log in")}
            <:subtitle>
              <%= if @current_scope do %>
                {gettext("You need to reauthenticate to perform sensitive actions on your account.")}
              <% else %>
                {gettext("Don't have an account?")} <.link
                  navigate={~p"/users/register"}
                  class="font-medium text-foreground hover:text-muted"
                  phx-no-format
                >{gettext("Sign up")}</.link> {gettext("for an account now.")}
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div
          :if={local_mail_adapter?()}
          class="flex items-start gap-3 rounded-xl border border-border bg-surface-secondary p-3 text-sm"
        >
          <.icon name="hero-information-circle" class="size-5 shrink-0 text-foreground" />
          <div class="text-muted">
            <p>{gettext("You are running the local mail adapter.")}</p>
            <p>
              {gettext("To see sent emails, visit")} <.link
                href="/dev/mailbox"
                class="text-foreground underline"
              >{gettext("the mailbox page")}</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="w-full">
            {gettext("Log in with email")} <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="flex items-center gap-3 text-xs text-muted">
          <span class="h-px flex-1 bg-separator"></span>
          {gettext("or")}
          <span class="h-px flex-1 bg-separator"></span>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label={gettext("Password")}
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button class="w-full" name={@form[:remember_me].name} value="true">
            {gettext("Log in and stay logged in")} <span aria-hidden="true">→</span>
          </.button>
          <.button variant="outline" class="mt-2 w-full">
            {gettext("Log in only this time")}
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      gettext(
        "If your email is in our system, you will receive instructions for logging in shortly."
      )

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:phoenix_chat, PhoenixChat.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
