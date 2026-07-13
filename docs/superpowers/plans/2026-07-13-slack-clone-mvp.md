# Slack Clone MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn phoenix_chat into a Slack-style team chat (channels, DMs, reactions, unread, presence) with the existing WebRTC video rooms kept as a per-channel "huddle" feature, styled per DESIGN.md (IBM Carbon).

**Architecture:** Single `ChatLive` LiveView shell (sidebar + active conversation) with `handle_params` navigation, LiveView streams for messages, one PubSub topic per channel, global Phoenix.Presence for online dots. DMs are `channels` rows with `kind: :dm`. `RoomChannel`/`RoomLive` remain solely for huddle WebRTC. Spec: `docs/superpowers/specs/2026-07-13-slack-clone-mvp-design.md`.

**Tech Stack:** Phoenix 1.8, LiveView 1.2, Ecto/Postgres 17 (Docker, port 5433), Tailwind v4 + daisyUI (retokened to Carbon), phx.gen.auth, gettext (sr default), IBM Plex Sans (vendored).

**Plan refinements over spec (approved direction, concretized):**
- `{:reaction_changed, ...}` broadcast carries the full preloaded message (LV needs author+body to re-render the stream entry), not just id+summary.
- Active sidebar item = `#e0e0e0` bg + 2px `#0f62fe` left rule + weight 600 (Carbon selected-nav; keeps blue scarce).
- All templates are written with `gettext("English msgid")` from the first task that creates them; Task 17 only extracts and adds `sr` translations.

## Global Constraints

Every task's requirements implicitly include this section.

- Elixir `~> 1.18`, Phoenix `~> 1.8.0`, LiveView `~> 1.2`, Postgres 17 via dedicated Docker container `phoenix-chat-db` on **port 5433** (5432 is occupied by another project's container — never touch `hubora-postgres`).
- Carbon palette (DESIGN.md): primary `#0f62fe`, ink `#161616`, ink-muted `#525252`, ink-subtle `#8c8c8c`, canvas `#ffffff`, surface-1 `#f4f4f4`, surface-2/hairline `#e0e0e0`, success `#24a148`, warning `#f1c21b`, error `#da1e28`.
- **0px border-radius on every element.** No drop shadows. 1px hairlines + surface change only. IBM Plex Sans weights 300/400/600. Body 14px with `letter-spacing: 0.16px`.
- Validation rules: message body 1–4000 chars (trimmed); channel name `^[a-z0-9\-]+$`, 2–40 chars; username `^[a-zA-Z0-9_.-]+$`, 2–30 chars; topic ≤ 120 chars.
- Emoji reaction palette (exact, ordered): `👍 ❤️ 😂 🎉 👀 ✅ 🔥 🙏`.
- All user-facing strings in templates/flash/errors: `gettext("English text")` (or `dgettext("errors", ...)`) from the moment they are written.
- Timestamps: `utc_datetime_usec` everywhere.
- Every task ends green: `mix test` passes, and the final task gate is `mix precommit` (compile --warnings-as-errors, format, unused deps check, test).
- Commit style: short imperative subject (repo uses plain style, no conventional-commit prefixes). Every commit:
  `git commit -m "<subject>" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"`

## File Structure

New/modified files (created in the task noted):

```
config/dev.exs, config/test.exs                      — DB port 5433 (T0)
lib/phoenix_chat/accounts*                           — phx.gen.auth output (T1), username (T2)
priv/repo/migrations/*_add_username_to_users.exs     — (T2)
priv/repo/migrations/*_create_channels.exs           — channels + memberships (T3)
lib/phoenix_chat/chat.ex                             — Chat context, grows T3→T8
lib/phoenix_chat/chat/channel.ex                     — (T3)
lib/phoenix_chat/chat/channel_membership.ex          — (T3)
priv/repo/migrations/*_create_messages.exs           — (T6)
lib/phoenix_chat/chat/message.ex                     — (T6)
priv/repo/migrations/*_create_message_reactions.exs  — (T8)
lib/phoenix_chat/chat/message_reaction.ex            — (T8)
test/phoenix_chat/chat_test.exs                      — context tests, grows T3→T8
test/support/fixtures/chat_fixtures.ex               — (T3)
assets/css/app.css                                   — Carbon retoken (T9), chat CSS (T10+)
priv/static/fonts/*.woff2                            — IBM Plex Sans (T9)
lib/phoenix_chat_web/components/layouts.ex           — minimal Carbon app layout (T9)
lib/phoenix_chat_web/components/layouts/root.html.heex — fonts, light-only (T9)
lib/phoenix_chat_web/live/chat_live.ex               — shell LV (T10, grows →T15)
lib/phoenix_chat_web/live/chat_live.html.heex        — (T10)
lib/phoenix_chat_web/live/chat_live/components.ex    — sidebar/message/modal components (T10)
assets/js/app.js                                     — ScrollToBottom, ComposerKeys hooks (T11)
test/phoenix_chat_web/live/chat_live_test.exs        — LV tests (T10, grows →T15)
lib/phoenix_chat_web/router.ex                       — auth scopes (T1), chat routes (T10), huddle (T16)
lib/phoenix_chat_web/live/room_live.ex + .html.heex  — huddle rework (T16)
test/phoenix_chat_web/live/room_live_test.exs        — rewritten (T16)
priv/gettext/sr/LC_MESSAGES/{default,errors}.po      — (T17)
priv/repo/seeds.exs                                  — (T18)
DELETED in T10: lobby_live.ex/.heex + test, page_controller.ex + page_html.ex + test
DELETED in T16: old /r/:room_id route and ?dn= handling
```

---

### Task 0: Dev database + green baseline

Port 5432 is occupied by an unrelated project's container (`hubora-postgres`). Stand up a dedicated Postgres 17 container on **5433** and point dev/test config at it.

**Files:**
- Modify: `config/dev.exs` (repo block, ~line 5)
- Modify: `config/test.exs` (repo block, ~line 8)

**Interfaces:**
- Produces: running Postgres at `localhost:5433`, user `postgres`, password `postgres`; `mix test` green baseline for all later tasks.

- [ ] **Step 1: Start the dedicated container**

```bash
docker run -d --name phoenix-chat-db -e POSTGRES_PASSWORD=postgres -p 5433:5432 --restart unless-stopped postgres:17
```

Expected: container id printed. Verify: `docker ps --filter name=phoenix-chat-db --format '{{.Status}}'` → starts with "Up". (If the container already exists from a previous run: `docker start phoenix-chat-db`.)

- [ ] **Step 2: Point dev and test config at port 5433**

In `config/dev.exs`, add `port: 5433,` to the repo config:

```elixir
config :phoenix_chat, PhoenixChat.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5433,
  database: "phoenix_chat_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
```

In `config/test.exs`, same addition:

```elixir
config :phoenix_chat, PhoenixChat.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5433,
  database: "phoenix_chat_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
```

- [ ] **Step 3: Verify baseline is green**

```bash
mix setup && mix test
```

Expected: `ecto.create`/`migrate` succeed (no migrations yet), assets build, and all existing tests pass (lobby, room, page controller, error views) — `0 failures`.

- [ ] **Step 4: Commit**

```bash
git add config/dev.exs config/test.exs
git commit -m "Point dev/test database at dedicated container on port 5433" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 1: Generate authentication (phx.gen.auth)

**Files:**
- Create (generated): `lib/phoenix_chat/accounts.ex`, `lib/phoenix_chat/accounts/{user,user_token,user_notifier,scope}.ex`, `lib/phoenix_chat_web/user_auth.ex`, `lib/phoenix_chat_web/live/user_live/*.ex`, `lib/phoenix_chat_web/controllers/user_session_controller.ex`, migration `*_create_users_auth_tables.exs`, `test/support/fixtures/accounts_fixtures.ex`, auth tests
- Modify (generated): `lib/phoenix_chat_web/router.ex`, `mix.exs` (adds `bcrypt_elixir`), `config/test.exs` (bcrypt rounds), `test/support/conn_case.ex` (adds `register_and_log_in_user/1`, `log_in_user/2`)

**Interfaces:**
- Produces: `PhoenixChat.Accounts.register_user/1`, `Accounts.get_user_by_email/1`, scope-based `@current_scope` assign (`socket.assigns.current_scope.user`), router `live_session :require_authenticated_user` block with `on_mount: [{PhoenixChatWeb.UserAuth, :require_authenticated}]`, ConnCase helpers `register_and_log_in_user/1` and `log_in_user/2`, fixture `PhoenixChat.AccountsFixtures.user_fixture/1`.

- [ ] **Step 1: Run the generator (LiveView flavor)**

```bash
mix phx.gen.auth Accounts User users --live
mix deps.get
```

Expected: files listed above created; router gains auth scopes. If the generator prompts for LiveView vs controllers, choose LiveView.

- [ ] **Step 2: Migrate and run the generated tests**

```bash
mix ecto.migrate && mix test
```

Expected: users/users_tokens tables created (with `citext` extension), all tests pass including generated auth tests, `0 failures`. The pre-existing `/` (LobbyLive) and `/r/:room_id` (RoomLive) routes are untouched and still pass.

- [ ] **Step 3: Record the generated shape for later tasks**

```bash
grep -n "def register_user\|def get_user_by_email\|defmodule" lib/phoenix_chat/accounts.ex | head
grep -n "live_session :require_authenticated_user" lib/phoenix_chat_web/router.ex
```

Expected: both exist. (Phoenix 1.8 generates magic-link-first auth: `register_user/1` inserts via `User.email_changeset/2-3`; login page offers magic link and optional password. Later tasks anchor on `register_user/1` and the `:require_authenticated_user` live_session — verify these names now; if your generated minor version differs, note the actual names and use them consistently in Tasks 2, 4, 10, 16.)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add authentication via phx.gen.auth (LiveView, scope-based)" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Username on users

Users need a display identity for chat. `username`: citext (case-insensitive unique), required at registration, 2–30 chars, `^[a-zA-Z0-9_.-]+$`.

**Files:**
- Create: `priv/repo/migrations/<ts>_add_username_to_users.exs`
- Modify: `lib/phoenix_chat/accounts/user.ex` (add field + changeset), `lib/phoenix_chat/accounts.ex` (register/changeset plumbing + `get_user_by_username/1`), registration LiveView `lib/phoenix_chat_web/live/user_live/registration.ex` (form field), `test/support/fixtures/accounts_fixtures.ex` (username in fixtures)
- Test: `test/phoenix_chat/accounts_test.exs` (extend generated file)

**Interfaces:**
- Consumes: `Accounts.register_user/1` (T1).
- Produces: `User.username` field; `Accounts.get_user_by_username(username :: String.t()) :: User.t() | nil`; `user_fixture/1` returns users with unique usernames; registration requires username.

- [ ] **Step 1: Write failing tests** (append inside the `describe "register_user/1"` block — or equivalent — in `test/phoenix_chat/accounts_test.exs`)

```elixir
    test "requires username" do
      {:error, changeset} = Accounts.register_user(%{email: unique_user_email()})
      assert "can't be blank" in errors_on(changeset).username
    end

    test "validates username format and length" do
      {:error, changeset} =
        Accounts.register_user(%{email: unique_user_email(), username: "no spaces!"})

      assert "only letters, numbers and _ . - allowed" in errors_on(changeset).username

      {:error, changeset} =
        Accounts.register_user(%{email: unique_user_email(), username: "a"})

      assert "should be at least 2 character(s)" in errors_on(changeset).username
    end

    test "enforces case-insensitive username uniqueness" do
      %{username: taken} = user_fixture()

      {:error, changeset} =
        Accounts.register_user(%{email: unique_user_email(), username: String.upcase(taken)})

      assert "has already been taken" in errors_on(changeset).username
    end

    test "get_user_by_username/1 returns the user" do
      user = user_fixture()
      assert Accounts.get_user_by_username(user.username).id == user.id
      assert Accounts.get_user_by_username("nope-nobody") == nil
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat/accounts_test.exs`
Expected: FAIL — existing fixtures don't set username yet / `get_user_by_username/1` undefined. (Generated tests may also start failing once the migration lands — that's expected until Step 5.)

- [ ] **Step 3: Migration**

```bash
mix ecto.gen.migration add_username_to_users
```

```elixir
defmodule PhoenixChat.Repo.Migrations.AddUsernameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :username, :citext, null: false
    end

    create unique_index(:users, [:username])
  end
end
```

(Fresh dev/test DBs have no users, so `null: false` is safe. `citext` extension is already enabled by the auth migration.)

- [ ] **Step 4: Schema + context changes**

In `lib/phoenix_chat/accounts/user.ex`, add to the `schema "users"` block:

```elixir
    field :username, :string
```

Add this public function to the same module (alongside the other changesets):

```elixir
  @doc """
  A user changeset for the username, required at registration.
  """
  def username_changeset(user_or_changeset, attrs) do
    user_or_changeset
    |> cast(attrs, [:username])
    |> validate_required([:username])
    |> validate_length(:username, min: 2, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_.-]+$/,
      message: "only letters, numbers and _ . - allowed"
    )
    |> unique_constraint(:username)
  end
```

In `lib/phoenix_chat/accounts.ex`:
1. Pipe registration through it — in `register_user/1`, pipe the existing changeset into `|> User.username_changeset(attrs)` before `Repo.insert()`.
2. Do the same in the function that builds the registration form changeset (`change_user_registration/2` if present; otherwise the `change_user_email/2` call used by the registration LiveView — add the pipe there only for the registration path).
3. Add:

```elixir
  @doc """
  Gets a user by username (case-insensitive). Returns nil if not found.
  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end
```

In `lib/phoenix_chat_web/live/user_live/registration.ex`, add the input to the form (directly above the email input):

```heex
        <.input
          field={@form[:username]}
          type="text"
          label={gettext("Username")}
          autocomplete="username"
          required
        />
```

- [ ] **Step 5: Fix fixtures**

In `test/support/fixtures/accounts_fixtures.ex`, add a unique-username helper and merge it into `valid_user_attributes/1` (the map the fixture passes to registration):

```elixir
  def unique_user_username, do: "user#{System.unique_integer([:positive])}"
```

and inside `valid_user_attributes/1` (or equivalent attrs builder), add `username: unique_user_username()` to the defaults map.

- [ ] **Step 6: Run the full suite**

Run: `mix ecto.migrate && mix test`
Expected: PASS, `0 failures` — new tests green, generated auth tests green (fixtures now provide usernames), registration LiveView test still green (it posts the attrs map from fixtures).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Require unique username at registration" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Chat context — channels & memberships

**Files:**
- Create: `priv/repo/migrations/<ts>_create_channels.exs`, `lib/phoenix_chat/chat.ex`, `lib/phoenix_chat/chat/channel.ex`, `lib/phoenix_chat/chat/channel_membership.ex`, `test/support/fixtures/chat_fixtures.ex`
- Test: `test/phoenix_chat/chat_test.exs`

**Interfaces:**
- Consumes: `PhoenixChat.Accounts.User`, `user_fixture/0` (T1/T2).
- Produces:
  - `Chat.create_channel(creator :: User.t(), attrs :: map()) :: {:ok, Channel.t()} | {:error, Changeset.t()}` (creator auto-joins)
  - `Chat.join_channel(user, channel) :: {:ok, ChannelMembership.t()}` (idempotent)
  - `Chat.member?(user, channel) :: boolean()`
  - `Chat.get_channel_by_slug!(slug) :: Channel.t()` (raises `Ecto.NoResultsError`)
  - `Chat.get_channel!(id) :: Channel.t()`
  - `Chat.list_joined_channels(user) :: [%{channel: Channel.t(), unread: non_neg_integer()}]` (kind `:channel`, name asc)
  - `Chat.list_browsable_channels(user) :: [Channel.t()]` (public channels not joined, name asc)
  - `Chat.ensure_general_channel!() :: Channel.t()` (idempotent)
  - `Chat.subscribe(channel) :: :ok` — subscribes caller to `"chat:channel:#{id}"` on `PhoenixChat.PubSub`
  - `ChatFixtures.channel_fixture(creator, attrs \\ %{})`
  - `Channel` fields: `id, name, slug, topic, kind (:channel | :dm), dm_key, inserted_at, updated_at`

- [ ] **Step 1: Write failing tests** — create `test/phoenix_chat/chat_test.exs`:

```elixir
defmodule PhoenixChat.ChatTest do
  use PhoenixChat.DataCase, async: true

  alias PhoenixChat.Chat
  alias PhoenixChat.Chat.Channel

  import PhoenixChat.AccountsFixtures
  import PhoenixChat.ChatFixtures

  describe "create_channel/2" do
    test "creates a public channel, slug = name, creator joins" do
      user = user_fixture()
      assert {:ok, %Channel{} = ch} = Chat.create_channel(user, %{name: "Proba-1", topic: "test"})
      assert ch.name == "proba-1"
      assert ch.slug == "proba-1"
      assert ch.kind == :channel
      assert Chat.member?(user, ch)
    end

    test "rejects invalid names" do
      user = user_fixture()
      assert {:error, cs} = Chat.create_channel(user, %{name: "has space"})
      assert "only lowercase letters, numbers and dashes" in errors_on(cs).name
      assert {:error, cs} = Chat.create_channel(user, %{name: "a"})
      assert "should be at least 2 character(s)" in errors_on(cs).name
      assert {:error, cs} = Chat.create_channel(user, %{name: ""})
      assert "can't be blank" in errors_on(cs).name
    end

    test "rejects duplicate channel names" do
      user = user_fixture()
      {:ok, _} = Chat.create_channel(user, %{name: "dupli"})
      assert {:error, cs} = Chat.create_channel(user, %{name: "dupli"})
      assert "has already been taken" in errors_on(cs).name
    end

    test "rejects topic over 120 chars" do
      user = user_fixture()
      long = String.duplicate("x", 121)
      assert {:error, cs} = Chat.create_channel(user, %{name: "ok-kanal", topic: long})
      assert "should be at most 120 character(s)" in errors_on(cs).topic
    end
  end

  describe "join_channel/2 and membership" do
    test "join is idempotent" do
      creator = user_fixture()
      other = user_fixture()
      ch = channel_fixture(creator)

      assert {:ok, _} = Chat.join_channel(other, ch)
      assert {:ok, _} = Chat.join_channel(other, ch)
      assert Chat.member?(other, ch)

      # scoped to this channel — Task 4 later adds auto-join to #general,
      # so a global membership count would not stay stable
      memberships =
        Repo.all(
          from m in PhoenixChat.Chat.ChannelMembership, where: m.channel_id == ^ch.id
        )

      assert length(memberships) == 2
    end

    test "member?/2 is false for non-members" do
      ch = channel_fixture(user_fixture())
      refute Chat.member?(user_fixture(), ch)
    end
  end

  describe "listing" do
    test "list_joined_channels/1 returns only joined, name asc, with unread 0" do
      me = user_fixture()
      other = user_fixture()
      _chb = channel_fixture(me, %{name: "bbb"})
      _cha = channel_fixture(me, %{name: "aaa"})
      _not_mine = channel_fixture(other, %{name: "tudji"})

      # membership-set assertions instead of an exact list — Task 4 later
      # auto-joins #general, which would add a row here
      rows = Chat.list_joined_channels(me)
      names = for %{channel: c} <- rows, do: c.name

      assert names == Enum.sort(names)
      assert "aaa" in names
      assert "bbb" in names
      refute "tudji" in names
      assert Enum.all?(rows, &(&1.unread == 0))
    end

    test "list_browsable_channels/1 returns public channels I have not joined" do
      me = user_fixture()
      other = user_fixture()
      _mine = channel_fixture(me, %{name: "moj"})
      theirs = channel_fixture(other, %{name: "njihov"})

      assert [%Channel{id: id}] = Chat.list_browsable_channels(me)
      assert id == theirs.id
    end
  end

  describe "ensure_general_channel!/0" do
    test "creates once, returns same row after" do
      ch1 = Chat.ensure_general_channel!()
      ch2 = Chat.ensure_general_channel!()
      assert ch1.id == ch2.id
      assert ch1.slug == "general"
    end
  end

  describe "get_channel_by_slug!/1" do
    test "returns the channel or raises" do
      ch = channel_fixture(user_fixture(), %{name: "nadji-me"})
      assert Chat.get_channel_by_slug!("nadji-me").id == ch.id
      assert_raise Ecto.NoResultsError, fn -> Chat.get_channel_by_slug!("nema") end
    end
  end
end
```

Create `test/support/fixtures/chat_fixtures.ex`:

```elixir
defmodule PhoenixChat.ChatFixtures do
  @moduledoc """
  Test helpers for creating PhoenixChat.Chat entities.
  """

  alias PhoenixChat.Chat

  def unique_channel_name, do: "kanal-#{System.unique_integer([:positive])}"

  def channel_fixture(creator, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: unique_channel_name()})
    {:ok, channel} = Chat.create_channel(creator, attrs)
    channel
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat/chat_test.exs`
Expected: FAIL — `PhoenixChat.Chat` module does not exist.

- [ ] **Step 3: Migration**

```bash
mix ecto.gen.migration create_channels
```

```elixir
defmodule PhoenixChat.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :topic, :string
      add :kind, :string, null: false, default: "channel"
      add :dm_key, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channels, [:slug])
    create unique_index(:channels, [:name], where: "kind = 'channel'", name: :channels_channel_name_index)
    create unique_index(:channels, [:dm_key])

    create table(:channel_memberships) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :last_read_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:channel_memberships, [:channel_id, :user_id])
    create index(:channel_memberships, [:user_id])
  end
end
```

- [ ] **Step 4: Schemas** — create `lib/phoenix_chat/chat/channel.ex`:

```elixir
defmodule PhoenixChat.Chat.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channels" do
    field :name, :string
    field :slug, :string
    field :topic, :string
    field :kind, Ecto.Enum, values: [:channel, :dm], default: :channel
    field :dm_key, :string

    has_many :memberships, PhoenixChat.Chat.ChannelMembership

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for creating a public channel (kind :channel). Slug mirrors the name."
  def create_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :topic])
    |> update_change(:name, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 40)
    |> validate_format(:name, ~r/^[a-z0-9\-]+$/,
      message: "only lowercase letters, numbers and dashes"
    )
    |> validate_length(:topic, max: 120)
    |> put_slug_from_name()
    |> unique_constraint(:name, name: :channels_channel_name_index)
    |> unique_constraint(:slug)
  end

  defp put_slug_from_name(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, name)
    end
  end
end
```

Create `lib/phoenix_chat/chat/channel_membership.ex`:

```elixir
defmodule PhoenixChat.Chat.ChannelMembership do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channel_memberships" do
    belongs_to :channel, PhoenixChat.Chat.Channel
    belongs_to :user, PhoenixChat.Accounts.User
    field :last_read_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:channel_id, :user_id])
    |> validate_required([:channel_id, :user_id])
    |> put_initial_last_read()
    |> unique_constraint([:channel_id, :user_id])
  end

  defp put_initial_last_read(changeset) do
    if get_field(changeset, :last_read_at) do
      changeset
    else
      put_change(changeset, :last_read_at, DateTime.utc_now())
    end
  end
end
```

- [ ] **Step 5: Context** — create `lib/phoenix_chat/chat.ex`:

```elixir
defmodule PhoenixChat.Chat do
  @moduledoc """
  Channels, direct messages, messages, reactions, unread tracking.
  """

  import Ecto.Query, warn: false

  alias PhoenixChat.Repo
  alias PhoenixChat.Accounts.User
  alias PhoenixChat.Chat.{Channel, ChannelMembership}

  ## PubSub

  @doc "Subscribes the caller to the channel's realtime topic."
  def subscribe(%Channel{} = channel) do
    Phoenix.PubSub.subscribe(PhoenixChat.PubSub, topic(channel))
  end

  defp topic(%Channel{id: id}), do: "chat:channel:#{id}"

  ## Channels

  def get_channel!(id), do: Repo.get!(Channel, id)

  def get_channel_by_slug!(slug), do: Repo.get_by!(Channel, slug: slug)

  def create_channel(%User{} = creator, attrs) do
    result =
      %Channel{kind: :channel}
      |> Channel.create_changeset(attrs)
      |> Repo.insert()

    with {:ok, channel} <- result do
      {:ok, _membership} = join_channel(creator, channel)
      {:ok, channel}
    end
  end

  @doc "Idempotent: joining twice is a no-op."
  def join_channel(%User{} = user, %Channel{} = channel) do
    %ChannelMembership{}
    |> ChannelMembership.changeset(%{user_id: user.id, channel_id: channel.id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:channel_id, :user_id])
  end

  def member?(%User{} = user, %Channel{} = channel) do
    Repo.exists?(
      from m in ChannelMembership,
        where: m.user_id == ^user.id and m.channel_id == ^channel.id
    )
  end

  def list_joined_channels(%User{} = user), do: memberships_with_unread(user, :channel)

  def list_browsable_channels(%User{} = user) do
    joined_ids =
      from m in ChannelMembership, where: m.user_id == ^user.id, select: m.channel_id

    Repo.all(
      from c in Channel,
        where: c.kind == :channel and c.id not in subquery(joined_ids),
        order_by: [asc: c.name]
    )
  end

  def ensure_general_channel! do
    case Repo.get_by(Channel, slug: "general") do
      nil ->
        Repo.insert!(%Channel{kind: :channel, name: "general", slug: "general"})

      %Channel{} = channel ->
        channel
    end
  end

  # Unread counting joins messages once that table exists (Task 6/7). Until then
  # the left join below is against an always-empty relation via a false condition.
  defp memberships_with_unread(user, kind) do
    Repo.all(
      from m in ChannelMembership,
        join: c in Channel,
        on: c.id == m.channel_id,
        where: m.user_id == ^user.id and c.kind == ^kind,
        order_by: [asc: c.name],
        select: %{channel: c, unread: 0}
    )
  end
end
```

- [ ] **Step 6: Run tests**

Run: `mix ecto.migrate && mix test`
Expected: PASS, `0 failures`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add Chat context with channels and memberships" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Auto-join #general at registration

**Files:**
- Modify: `lib/phoenix_chat/chat.ex` (add `join_general/1`), `lib/phoenix_chat/accounts.ex` (`register_user/1`)
- Test: `test/phoenix_chat/accounts_test.exs`

**Interfaces:**
- Consumes: `Chat.ensure_general_channel!/0`, `Chat.join_channel/2` (T3); `Accounts.register_user/1` (T1).
- Produces: `Chat.join_general(user) :: {:ok, ChannelMembership.t()}`; every registered user is a member of `#general`.

- [ ] **Step 1: Write failing test** (append to `test/phoenix_chat/accounts_test.exs`, inside the `register_user/1` describe block):

```elixir
    test "auto-joins the general channel" do
      {:ok, user} = Accounts.register_user(valid_user_attributes())
      general = PhoenixChat.Chat.ensure_general_channel!()
      assert PhoenixChat.Chat.member?(user, general)
    end
```

(If the generated attrs builder is named differently than `valid_user_attributes/0`, use the name found in `accounts_fixtures.ex`.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat/accounts_test.exs`
Expected: FAIL — user is not a member of general.

- [ ] **Step 3: Implement**

Add to `lib/phoenix_chat/chat.ex` (below `ensure_general_channel!/0`):

```elixir
  def join_general(%User{} = user) do
    join_channel(user, ensure_general_channel!())
  end
```

In `lib/phoenix_chat/accounts.ex`, wrap the insert result in `register_user/1`:

```elixir
    # after the existing changeset |> Repo.insert() pipeline:
    with {:ok, user} <- result do
      {:ok, _} = PhoenixChat.Chat.join_general(user)
      {:ok, user}
    end
```

(bind the existing pipeline to `result =` first; keep everything else as generated.)

- [ ] **Step 4: Run the full suite**

Run: `mix test`
Expected: PASS, `0 failures` (generated auth tests exercise `register_user/1` heavily — they must all still pass).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Auto-join general channel at registration" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Direct messages — get_or_create_dm!

**Files:**
- Modify: `lib/phoenix_chat/chat.ex`
- Test: `test/phoenix_chat/chat_test.exs`

**Interfaces:**
- Consumes: T3 schema (`channels.dm_key` unique index), `join_channel/2`.
- Produces:
  - `Chat.get_or_create_dm!(a :: User.t(), b :: User.t()) :: Channel.t()` — same row for both argument orders; both users are members; raises `FunctionClauseError` on self-DM
  - `Chat.dm_other_user(channel, me) :: User.t()`
  - `Chat.list_dm_channels(user) :: [%{channel: Channel.t(), other_user: User.t(), unread: non_neg_integer()}]`

- [ ] **Step 1: Write failing tests** (append a describe block to `test/phoenix_chat/chat_test.exs`):

```elixir
  describe "direct messages" do
    test "get_or_create_dm!/2 creates once and dedups both orderings" do
      a = user_fixture()
      b = user_fixture()

      dm1 = Chat.get_or_create_dm!(a, b)
      dm2 = Chat.get_or_create_dm!(b, a)

      assert dm1.id == dm2.id
      assert dm1.kind == :dm
      assert dm1.dm_key == "#{min(a.id, b.id)}:#{max(a.id, b.id)}"
      assert Chat.member?(a, dm1)
      assert Chat.member?(b, dm1)
    end

    test "self-DM is not allowed" do
      a = user_fixture()
      assert_raise FunctionClauseError, fn -> Chat.get_or_create_dm!(a, a) end
    end

    test "dm_other_user/2 returns the counterpart" do
      a = user_fixture()
      b = user_fixture()
      dm = Chat.get_or_create_dm!(a, b)

      assert Chat.dm_other_user(dm, a).id == b.id
      assert Chat.dm_other_user(dm, b).id == a.id
    end

    test "list_dm_channels/1 lists my DMs with the other user attached" do
      a = user_fixture()
      b = user_fixture()
      dm = Chat.get_or_create_dm!(a, b)

      assert [%{channel: %{id: id}, other_user: other, unread: 0}] = Chat.list_dm_channels(a)
      assert id == dm.id
      assert other.id == b.id

      assert Chat.list_dm_channels(user_fixture()) == []
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat/chat_test.exs`
Expected: FAIL — `get_or_create_dm!/2` undefined.

- [ ] **Step 3: Implement** — add to `lib/phoenix_chat/chat.ex` (new `## Direct messages` section):

```elixir
  ## Direct messages

  @doc """
  Returns the DM channel between two distinct users, creating it (and both
  memberships) on first use. Safe under races via the unique dm_key index.
  """
  def get_or_create_dm!(%User{id: a_id} = a, %User{id: b_id} = b) when a_id != b_id do
    key = dm_key(a_id, b_id)

    case Repo.get_by(Channel, dm_key: key) do
      %Channel{} = channel ->
        channel

      nil ->
        {:ok, channel} =
          Repo.transaction(fn ->
            channel =
              case Repo.insert(%Channel{kind: :dm, name: key, slug: "dm-" <> key, dm_key: key}) do
                {:ok, channel} -> channel
                # lost a creation race — the row exists now
                {:error, _changeset} -> Repo.get_by!(Channel, dm_key: key)
              end

            {:ok, _} = join_channel(a, channel)
            {:ok, _} = join_channel(b, channel)
            channel
          end)

        channel
    end
  end

  defp dm_key(id1, id2), do: "#{min(id1, id2)}:#{max(id1, id2)}"

  def dm_other_user(%Channel{kind: :dm} = channel, %User{} = me) do
    Repo.one!(
      from u in User,
        join: m in ChannelMembership,
        on: m.user_id == u.id,
        where: m.channel_id == ^channel.id and u.id != ^me.id
    )
  end

  def list_dm_channels(%User{} = user) do
    for %{channel: channel} = row <- memberships_with_unread(user, :dm) do
      Map.put(row, :other_user, dm_other_user(channel, user))
    end
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test`
Expected: PASS, `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add DM channels with dm_key dedup" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Messages — send, list, paginate, broadcast

**Files:**
- Create: `priv/repo/migrations/<ts>_create_messages.exs`, `lib/phoenix_chat/chat/message.ex`
- Modify: `lib/phoenix_chat/chat.ex` (messages section + real unread join), `test/support/fixtures/chat_fixtures.ex`
- Test: `test/phoenix_chat/chat_test.exs`

**Interfaces:**
- Consumes: T3/T5 (`Channel`, memberships, `subscribe/1`).
- Produces:
  - `Chat.send_message(user, channel, attrs :: %{body: String.t()}) :: {:ok, Message.t()} | {:error, Changeset.t()} | {:error, :not_a_member}` — on success broadcasts `{:new_message, %Message{user: %User{}}}` to `"chat:channel:#{id}"`
  - `Chat.list_messages(channel, opts \\ []) :: {[Message.t()], older_cursor :: integer() | nil}` — ascending order, `:limit` (default 50), `:before_id`; messages have `:user` preloaded; cursor is the oldest returned id when a full page came back, else nil
  - `Chat.get_message!(id) :: Message.t()` with `:user` preloaded
  - `Message` fields: `id, channel_id, user_id, body, inserted_at`
  - `ChatFixtures.message_fixture(user, channel, attrs \\ %{})`

- [ ] **Step 1: Write failing tests** (append to `test/phoenix_chat/chat_test.exs`):

```elixir
  describe "messages" do
    setup do
      user = user_fixture()
      channel = channel_fixture(user)
      %{user: user, channel: channel}
    end

    test "send_message/3 stores, trims, preloads user and broadcasts", %{user: user, channel: channel} do
      :ok = Chat.subscribe(channel)

      assert {:ok, msg} = Chat.send_message(user, channel, %{body: "  zdravo svima  "})
      assert msg.body == "zdravo svima"
      assert msg.user.id == user.id

      assert_receive {:new_message, %{id: id, body: "zdravo svima"}}
      assert id == msg.id
    end

    test "send_message/3 validates body", %{user: user, channel: channel} do
      assert {:error, cs} = Chat.send_message(user, channel, %{body: "   "})
      assert "can't be blank" in errors_on(cs).body

      too_long = String.duplicate("x", 4001)
      assert {:error, cs} = Chat.send_message(user, channel, %{body: too_long})
      assert "should be at most 4000 character(s)" in errors_on(cs).body
    end

    test "send_message/3 refuses non-members", %{channel: channel} do
      stranger = user_fixture()
      assert {:error, :not_a_member} = Chat.send_message(stranger, channel, %{body: "upad"})
    end

    test "list_messages/2 returns ascending with cursor pagination", %{user: user, channel: channel} do
      for i <- 1..7, do: message_fixture(user, channel, %{body: "poruka #{i}"})

      {page, cursor} = Chat.list_messages(channel, limit: 5)
      assert Enum.map(page, & &1.body) == for(i <- 3..7, do: "poruka #{i}")
      assert cursor == List.first(page).id

      {older, older_cursor} = Chat.list_messages(channel, limit: 5, before_id: cursor)
      assert Enum.map(older, & &1.body) == ["poruka 1", "poruka 2"]
      assert older_cursor == nil
    end
  end
```

Add to `test/support/fixtures/chat_fixtures.ex`:

```elixir
  def message_fixture(user, channel, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{body: "poruka #{System.unique_integer([:positive])}"})
    {:ok, message} = Chat.send_message(user, channel, attrs)
    message
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat/chat_test.exs`
Expected: FAIL — `send_message/3` undefined.

- [ ] **Step 3: Migration**

```bash
mix ecto.gen.migration create_messages
```

```elixir
defmodule PhoenixChat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:channel_id, :id])
  end
end
```

- [ ] **Step 4: Schema** — create `lib/phoenix_chat/chat/message.ex`:

```elixir
defmodule PhoenixChat.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :body, :string
    belongs_to :channel, PhoenixChat.Chat.Channel
    belongs_to :user, PhoenixChat.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 4000)
  end
end
```

- [ ] **Step 5: Context functions** — in `lib/phoenix_chat/chat.ex`:

Add `Message` to the alias line:

```elixir
  alias PhoenixChat.Chat.{Channel, ChannelMembership, Message}
```

Add a broadcast helper next to `topic/1`:

```elixir
  defp broadcast!(%Channel{} = channel, event) do
    Phoenix.PubSub.broadcast!(PhoenixChat.PubSub, topic(channel), event)
  end
```

New `## Messages` section:

```elixir
  ## Messages

  def get_message!(id) do
    Message |> Repo.get!(id) |> Repo.preload(:user)
  end

  def send_message(%User{} = user, %Channel{} = channel, attrs) do
    if member?(user, channel) do
      result =
        %Message{user_id: user.id, channel_id: channel.id}
        |> Message.changeset(attrs)
        |> Repo.insert()

      with {:ok, message} <- result do
        message = %{message | user: user}
        broadcast!(channel, {:new_message, message})
        {:ok, message}
      end
    else
      {:error, :not_a_member}
    end
  end

  @doc """
  Newest page of messages in ascending order plus a cursor for older pages.
  Cursor is nil when there is nothing older.
  """
  def list_messages(%Channel{} = channel, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before_id)

    query =
      from m in Message,
        where: m.channel_id == ^channel.id,
        order_by: [desc: m.id],
        limit: ^limit,
        preload: [:user]

    query = if before_id, do: where(query, [m], m.id < ^before_id), else: query

    messages = query |> Repo.all() |> Enum.reverse()

    cursor =
      if length(messages) == limit, do: List.first(messages).id, else: nil

    {messages, cursor}
  end
```

Replace `memberships_with_unread/2` with the real unread computation (own messages excluded):

```elixir
  defp memberships_with_unread(user, kind) do
    Repo.all(
      from m in ChannelMembership,
        join: c in Channel,
        on: c.id == m.channel_id,
        where: m.user_id == ^user.id and c.kind == ^kind,
        left_join: msg in Message,
        on:
          msg.channel_id == c.id and msg.inserted_at > m.last_read_at and
            msg.user_id != ^user.id,
        group_by: c.id,
        order_by: [asc: c.name],
        select: %{channel: c, unread: count(msg.id)}
    )
  end
```

- [ ] **Step 6: Run tests**

Run: `mix ecto.migrate && mix test`
Expected: PASS, `0 failures`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add persistent messages with pagination and PubSub broadcast" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Unread — mark_read & unread_count

**Files:**
- Modify: `lib/phoenix_chat/chat.ex`
- Test: `test/phoenix_chat/chat_test.exs`

**Interfaces:**
- Consumes: T6 messages, `memberships_with_unread/2`.
- Produces:
  - `Chat.mark_read(user, channel) :: :ok` — bumps membership `last_read_at` to now
  - `Chat.unread_count(user, channel) :: non_neg_integer()` — messages newer than `last_read_at`, excluding own; 0 for non-members

- [ ] **Step 1: Write failing tests** (append to `test/phoenix_chat/chat_test.exs`):

```elixir
  describe "unread tracking" do
    test "unread counts exclude own messages and reset on mark_read" do
      me = user_fixture()
      other = user_fixture()
      channel = channel_fixture(me)
      {:ok, _} = Chat.join_channel(other, channel)

      message_fixture(me, channel, %{body: "moja"})
      message_fixture(other, channel, %{body: "tudja 1"})
      message_fixture(other, channel, %{body: "tudja 2"})

      assert Chat.unread_count(me, channel) == 2

      assert %{unread: 2} =
               Enum.find(Chat.list_joined_channels(me), &(&1.channel.id == channel.id))

      assert :ok = Chat.mark_read(me, channel)
      assert Chat.unread_count(me, channel) == 0

      assert %{unread: 0} =
               Enum.find(Chat.list_joined_channels(me), &(&1.channel.id == channel.id))
    end

    test "unread_count/2 is 0 for non-members" do
      channel = channel_fixture(user_fixture())
      assert Chat.unread_count(user_fixture(), channel) == 0
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat/chat_test.exs`
Expected: FAIL — `unread_count/2` undefined.

Note: memberships are created with `last_read_at = now`, and message fixtures insert *after* that moment, so the counts above are deterministic (timestamps are `usec` precision).

- [ ] **Step 3: Implement** — add to `lib/phoenix_chat/chat.ex` (new `## Unread` section):

```elixir
  ## Unread

  def mark_read(%User{} = user, %Channel{} = channel) do
    now = DateTime.utc_now()

    from(m in ChannelMembership,
      where: m.user_id == ^user.id and m.channel_id == ^channel.id
    )
    |> Repo.update_all(set: [last_read_at: now])

    :ok
  end

  def unread_count(%User{} = user, %Channel{} = channel) do
    case Repo.get_by(ChannelMembership, user_id: user.id, channel_id: channel.id) do
      nil ->
        0

      %ChannelMembership{last_read_at: last_read_at} ->
        Repo.aggregate(
          from(m in Message,
            where:
              m.channel_id == ^channel.id and m.inserted_at > ^last_read_at and
                m.user_id != ^user.id
          ),
          :count
        )
    end
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test`
Expected: PASS, `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add unread tracking via membership last_read_at" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Reactions — toggle + summary

**Files:**
- Create: `priv/repo/migrations/<ts>_create_message_reactions.exs`, `lib/phoenix_chat/chat/message_reaction.ex`
- Modify: `lib/phoenix_chat/chat.ex`, `lib/phoenix_chat/chat/message.ex` (has_many), `test/support/fixtures/chat_fixtures.ex` (no change needed — noted for completeness)
- Test: `test/phoenix_chat/chat_test.exs`

**Interfaces:**
- Consumes: T6 messages.
- Produces:
  - `Chat.reaction_palette() :: [String.t()]` — the 8 emoji, ordered
  - `Chat.toggle_reaction(user, message, emoji) :: :ok | {:error, :invalid_emoji} | {:error, :not_a_member}` — broadcasts `{:reaction_changed, %Message{user: ..., reactions: [...]}}` on the message's channel topic
  - `Chat.summarize_reactions(reactions :: [MessageReaction.t()], me_id :: integer()) :: [%{emoji: String.t(), count: pos_integer(), mine: boolean()}]` — palette order
  - `Chat.get_message!/1` and `Chat.list_messages/2` now preload `:reactions` too
  - `Chat.send_message/3` broadcast payload now carries `reactions: []`

- [ ] **Step 1: Write failing tests** (append to `test/phoenix_chat/chat_test.exs`):

```elixir
  describe "reactions" do
    setup do
      user = user_fixture()
      channel = channel_fixture(user)
      message = message_fixture(user, channel)
      %{user: user, channel: channel, message: message}
    end

    test "toggle adds then removes, and broadcasts", %{user: user, channel: channel, message: message} do
      :ok = Chat.subscribe(channel)

      assert :ok = Chat.toggle_reaction(user, message, "👍")
      assert_receive {:reaction_changed, %{id: mid, reactions: [%{emoji: "👍"}]}}
      assert mid == message.id

      assert :ok = Chat.toggle_reaction(user, message, "👍")
      assert_receive {:reaction_changed, %{reactions: []}}
    end

    test "rejects emoji outside the palette", %{user: user, message: message} do
      assert {:error, :invalid_emoji} = Chat.toggle_reaction(user, message, "🤡")
    end

    test "rejects non-members", %{message: message} do
      assert {:error, :not_a_member} = Chat.toggle_reaction(user_fixture(), message, "👍")
    end

    test "summarize_reactions/2 groups, counts, flags mine, palette order", %{
      user: user,
      channel: channel,
      message: message
    } do
      other = user_fixture()
      {:ok, _} = Chat.join_channel(other, channel)

      :ok = Chat.toggle_reaction(other, message, "🔥")
      :ok = Chat.toggle_reaction(user, message, "🔥")
      :ok = Chat.toggle_reaction(other, message, "👍")

      reactions = Chat.get_message!(message.id).reactions

      assert [
               %{emoji: "👍", count: 1, mine: false},
               %{emoji: "🔥", count: 2, mine: true}
             ] = Chat.summarize_reactions(reactions, user.id)
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat/chat_test.exs`
Expected: FAIL — `toggle_reaction/3` undefined.

- [ ] **Step 3: Migration**

```bash
mix ecto.gen.migration create_message_reactions
```

```elixir
defmodule PhoenixChat.Repo.Migrations.CreateMessageReactions do
  use Ecto.Migration

  def change do
    create table(:message_reactions) do
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :emoji, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:message_reactions, [:message_id, :user_id, :emoji])
    create index(:message_reactions, [:user_id])
  end
end
```

- [ ] **Step 4: Schema** — create `lib/phoenix_chat/chat/message_reaction.ex`:

```elixir
defmodule PhoenixChat.Chat.MessageReaction do
  use Ecto.Schema

  schema "message_reactions" do
    belongs_to :message, PhoenixChat.Chat.Message
    belongs_to :user, PhoenixChat.Accounts.User
    field :emoji, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
```

Add to `lib/phoenix_chat/chat/message.ex`, inside the schema block:

```elixir
    has_many :reactions, PhoenixChat.Chat.MessageReaction
```

- [ ] **Step 5: Context changes** — in `lib/phoenix_chat/chat.ex`:

Extend the alias:

```elixir
  alias PhoenixChat.Chat.{Channel, ChannelMembership, Message, MessageReaction}
```

Add module attribute (top of module, under `@moduledoc`):

```elixir
  @reaction_palette ~w(👍 ❤️ 😂 🎉 👀 ✅ 🔥 🙏)
```

Update the two preloads and the send broadcast:
- `get_message!/1`: `Repo.preload([:user, :reactions])`
- `list_messages/2` query preload: `preload: [:user, :reactions]`
- `send_message/3` success branch: `message = %{message | user: user, reactions: []}`

New `## Reactions` section:

```elixir
  ## Reactions

  def reaction_palette, do: @reaction_palette

  def toggle_reaction(%User{} = user, %Message{} = message, emoji)
      when emoji in @reaction_palette do
    channel = get_channel!(message.channel_id)

    if member?(user, channel) do
      case Repo.get_by(MessageReaction,
             message_id: message.id,
             user_id: user.id,
             emoji: emoji
           ) do
        nil ->
          %MessageReaction{message_id: message.id, user_id: user.id, emoji: emoji}
          |> Repo.insert!()

        %MessageReaction{} = reaction ->
          Repo.delete!(reaction)
      end

      broadcast!(channel, {:reaction_changed, get_message!(message.id)})
      :ok
    else
      {:error, :not_a_member}
    end
  end

  def toggle_reaction(%User{}, %Message{}, _emoji), do: {:error, :invalid_emoji}

  @doc "Groups preloaded reactions into `%{emoji, count, mine}` rows in palette order."
  def summarize_reactions(reactions, me_id) when is_list(reactions) do
    grouped = Enum.group_by(reactions, & &1.emoji)

    for emoji <- @reaction_palette, rows = grouped[emoji], rows != nil do
      %{emoji: emoji, count: length(rows), mine: Enum.any?(rows, &(&1.user_id == me_id))}
    end
  end
```

- [ ] **Step 6: Run tests**

Run: `mix ecto.migrate && mix test`
Expected: PASS, `0 failures`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add emoji reactions with fixed palette" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Carbon visual foundation

Retoken daisyUI to Carbon values (this restyles every existing core component — buttons, inputs, flash — in one move), vendor IBM Plex Sans, force light-only theme, and slim `Layouts.app` down to a Carbon top-nav used by auth/settings pages. No behavior change: the whole existing test suite must stay green.

**Files:**
- Create: `priv/static/fonts/ibm-plex-sans-{latin,latin-ext}-{300,400,600}.woff2` (6 files)
- Modify: `assets/css/app.css`, `lib/phoenix_chat_web/components/layouts/root.html.heex`, `lib/phoenix_chat_web/components/layouts.ex`, `assets/js/app.js` (topbar color only)

**Interfaces:**
- Consumes: nothing new.
- Produces: daisyUI classes (`btn`, `btn-primary`, `input`, `alert`…) render Carbon-flat; CSS custom properties `--color-base-100/200/300`, `--color-base-content`, `--color-primary` = Carbon palette; `Layouts.app` renders a 48px top-nav + centered content column (auth pages look Carbon without further work); full-bleed `body` (no max-width/padding) for T10's shell.

- [ ] **Step 1: Vendor the fonts**

```bash
mkdir -p priv/static/fonts
for w in 300 400 600; do
  curl -fsSL -o priv/static/fonts/ibm-plex-sans-latin-$w.woff2 \
    "https://cdn.jsdelivr.net/fontsource/fonts/ibm-plex-sans@latest/latin-$w-normal.woff2"
  curl -fsSL -o priv/static/fonts/ibm-plex-sans-latin-ext-$w.woff2 \
    "https://cdn.jsdelivr.net/fontsource/fonts/ibm-plex-sans@latest/latin-ext-$w-normal.woff2"
done
ls -la priv/static/fonts/
```

Expected: 6 `.woff2` files, each > 10KB. (latin-ext is required — Serbian Latin diacritics č ć đ š ž live there.)

- [ ] **Step 2: Rewrite the theme section of `assets/css/app.css`**

Replace BOTH existing `@plugin "../vendor/daisyui-theme"` blocks (the "dark" one and the "light" one) with this single Carbon light theme, and delete the `@custom-variant dark (...)` line:

```css
@plugin "../vendor/daisyui-theme" {
  name: "light";
  default: true;
  prefersdark: false;
  color-scheme: "light";
  /* Carbon (DESIGN.md) mapped onto daisyUI slots */
  --color-base-100: #ffffff;   /* canvas */
  --color-base-200: #f4f4f4;   /* surface-1 */
  --color-base-300: #e0e0e0;   /* surface-2 / hairline */
  --color-base-content: #161616;  /* ink */
  --color-primary: #0f62fe;    /* IBM Blue */
  --color-primary-content: #ffffff;
  --color-secondary: #161616;  /* Carbon button-secondary is charcoal */
  --color-secondary-content: #ffffff;
  --color-accent: #0f62fe;
  --color-accent-content: #ffffff;
  --color-neutral: #525252;    /* ink-muted */
  --color-neutral-content: #ffffff;
  --color-info: #0f62fe;
  --color-info-content: #ffffff;
  --color-success: #24a148;
  --color-success-content: #ffffff;
  --color-warning: #f1c21b;
  --color-warning-content: #161616;
  --color-error: #da1e28;
  --color-error-content: #ffffff;
  /* Flat-square: the Carbon signature */
  --radius-selector: 0rem;
  --radius-field: 0rem;
  --radius-box: 0rem;
  --size-selector: 0.21875rem;
  --size-field: 0.21875rem;
  --border: 1px;
  --depth: 0;
  --noise: 0;
}
```

- [ ] **Step 3: Fonts, base typography, and removal of the PoC body rule**

In the same file, directly after the `@plugin` blocks, add the `@font-face` declarations and a Tailwind `@theme` font override:

```css
/* IBM Plex Sans — vendored, latin + latin-ext (Serbian diacritics) */
@font-face {
  font-family: "IBM Plex Sans";
  font-style: normal;
  font-weight: 300;
  font-display: swap;
  src: url("/fonts/ibm-plex-sans-latin-ext-300.woff2") format("woff2");
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
}
@font-face {
  font-family: "IBM Plex Sans";
  font-style: normal;
  font-weight: 300;
  font-display: swap;
  src: url("/fonts/ibm-plex-sans-latin-300.woff2") format("woff2");
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}
@font-face {
  font-family: "IBM Plex Sans";
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url("/fonts/ibm-plex-sans-latin-ext-400.woff2") format("woff2");
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
}
@font-face {
  font-family: "IBM Plex Sans";
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url("/fonts/ibm-plex-sans-latin-400.woff2") format("woff2");
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}
@font-face {
  font-family: "IBM Plex Sans";
  font-style: normal;
  font-weight: 600;
  font-display: swap;
  src: url("/fonts/ibm-plex-sans-latin-ext-600.woff2") format("woff2");
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
}
@font-face {
  font-family: "IBM Plex Sans";
  font-style: normal;
  font-weight: 600;
  font-display: swap;
  src: url("/fonts/ibm-plex-sans-latin-600.woff2") format("woff2");
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}

@theme {
  --font-sans: "IBM Plex Sans", "Helvetica Neue", Arial, sans-serif;
  --default-font-family: var(--font-sans);
}

/* Carbon base voice: 14px body with 0.16px tracking, flat corners everywhere */
html {
  font-family: var(--font-sans);
}

body {
  font-size: 14px;
  letter-spacing: 0.16px;
  color: #161616;
  background: #ffffff;
}

* {
  border-radius: 0 !important;
}
```

Then DELETE from the PoC section lower in the file (the block that starts with `/* Root variables and base */`): the whole `body { margin... max-width... }` rule and its `@media (min-width: 1024px) { body { padding: 1.5rem; } }` companion. The `#video-grid`, `#controls-bar`, `#participants`, `#chat-panel` etc. rules STAY for now (RoomLive still uses them until Task 16).

- [ ] **Step 4: Light-only root layout** — rewrite `lib/phoenix_chat_web/components/layouts/root.html.heex`:

```heex
<!DOCTYPE html>
<html lang="en" data-theme="light">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <.live_title default="PhoenixChat">
      {assigns[:page_title]}
    </.live_title>
    <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
    </script>
  </head>

  <body>{@inner_content}</body>
</html>
```

(The theme-switching script and `" · Phoenix Framework"` title suffix are removed; the app is light-only per DESIGN.md.)

- [ ] **Step 5: Carbon `Layouts.app`** — in `lib/phoenix_chat_web/components/layouts.ex`, replace the `app/1` function and DELETE the now-unused `theme_toggle/1` function entirely:

```elixir
  def app(assigns) do
    ~H"""
    <header class="h-12 flex items-center justify-between px-4 bg-white border-b border-[#e0e0e0]">
      <a href="/" class="flex items-center gap-2">
        <span class="w-4 h-4 bg-[#0f62fe]" aria-hidden="true"></span>
        <span class="text-sm font-semibold text-[#161616]">PhoenixChat</span>
      </a>
      <div :if={@current_scope} class="flex items-center gap-4 text-sm">
        <span class="text-[#525252]">{@current_scope.user.username}</span>
        <.link href={~p"/users/settings"} class="text-[#0f62fe] hover:underline">
          {gettext("Settings")}
        </.link>
        <.link href={~p"/users/log-out"} method="delete" class="text-[#0f62fe] hover:underline">
          {gettext("Log out")}
        </.link>
      </div>
    </header>

    <main class="px-4 py-16">
      <div class="mx-auto max-w-md space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end
```

Note: if the generated log-out route differs (`/users/log_out` in some versions), match whatever Task 1 generated — check with `grep "log.out" lib/phoenix_chat_web/router.ex`.
Guard: `@current_scope.user.username` renders only when `@current_scope` is set (auth pages pass it; pre-T10 lobby/room pass `current_scope={assigns[:current_scope]}` which is nil → the `:if` skips the block).

- [ ] **Step 6: Topbar color** — in `assets/js/app.js`, change the topbar config line to Carbon blue:

```js
topbar.config({barColors: {0: "#0f62fe"}, shadowColor: "rgba(0, 0, 0, .3)"})
```

- [ ] **Step 7: Verify**

Run: `mix assets.build && mix test`
Expected: assets compile without warnings; full suite PASS, `0 failures`.
Then `mix phx.server` and eyeball http://localhost:4000/users/log-in — square inputs/buttons, Plex Sans, blue primary button. Stop the server.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Retoken UI to IBM Carbon: Plex Sans, flat corners, light-only" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: ChatLive shell — routes, sidebar, send/receive

The core screen: authenticated shell with channel sidebar and active-channel message view. Replaces the lobby. Message grouping/day dividers/pagination polish comes in T11; unread live-updates in T12; DMs in T13; reactions UI in T14; modals in T15.

**Files:**
- Create: `lib/phoenix_chat_web/live/chat_live.ex`, `lib/phoenix_chat_web/live/chat_live.html.heex`, `lib/phoenix_chat_web/live/chat_live/components.ex`, `test/phoenix_chat_web/live/chat_live_test.exs`
- Modify: `lib/phoenix_chat_web/router.ex`, `assets/css/app.css` (append chat CSS)
- Delete: `lib/phoenix_chat_web/live/lobby_live.ex`, `lib/phoenix_chat_web/live/lobby_live.html.heex`, `test/phoenix_chat_web/live/lobby_live_test.exs`, `lib/phoenix_chat_web/controllers/page_controller.ex`, `lib/phoenix_chat_web/controllers/page_html.ex`, `lib/phoenix_chat_web/controllers/page_html/` (dir), `test/phoenix_chat_web/controllers/page_controller_test.exs`

**Interfaces:**
- Consumes: `Chat.list_joined_channels/1`, `list_dm_channels/1`, `get_channel_by_slug!/1`, `subscribe/1`, `mark_read/2`, `list_messages/2`, `send_message/3`, `summarize_reactions/2` (T3–T8); `register_and_log_in_user/1` ConnCase helper (T1).
- Produces:
  - Routes `/` (`:index`) and `/c/:slug` (`:channel`) → `PhoenixChatWeb.ChatLive` inside the generated `live_session :require_authenticated_user`
  - `ChatLive` assigns contract: `@channels`/`@dms` (`[%{channel:, unread:, ...}]`), `@active :: Channel.t() | nil`, `@conversation_title`, `@newest :: Message.t() | nil`, `@older_cursor`, `@messages_empty?`, `@form`
  - stream `:messages` of entries `%{id, user_id, username, body, inserted_at, reactions}`
  - `PhoenixChatWeb.ChatComponents` with `sidebar_item/1`, `message_entry/1`, `channel_header/1`
  - private helpers later tasks extend: `open_conversation/2`, `build_entries/2`, `build_entry/3`, `clear_unread/2`, `current_user/1`
  - CSS classes `cds-shell`, `cds-sidebar*`, `cds-main`, `cds-channel-header`, `cds-messages`, `cds-message*`, `cds-avatar`, `cds-composer*`, `cds-btn-primary`, `cds-btn-tertiary`, `cds-unread-badge`, `cds-section-label`, `cds-empty`

- [ ] **Step 1: Write failing tests** — create `test/phoenix_chat_web/live/chat_live_test.exs`:

```elixir
defmodule PhoenixChatWeb.ChatLiveTest do
  use PhoenixChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PhoenixChat.AccountsFixtures
  import PhoenixChat.ChatFixtures

  alias PhoenixChat.Chat

  test "redirects anonymous visitors to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  describe "channel view" do
    setup :register_and_log_in_user

    test "/ patches to #general", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert_patch(view, ~p"/c/general")
      assert has_element?(view, ".cds-channel-name", "#general")
    end

    test "sends a message and renders it", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      view
      |> form("#composer", message: %{body: "prva poruka"})
      |> render_submit()

      assert has_element?(view, "#message-list", "prva poruka")
      assert has_element?(view, "#message-list", user.username)
    end

    test "rejects an empty message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      html =
        view
        |> form("#composer", message: %{body: "   "})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "receives another member's message in real time", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      other = user_fixture()
      general = Chat.get_channel_by_slug!("general")
      {:ok, _} = Chat.send_message(other, general, %{body: "zdravo iz drugog procesa"})

      assert render(view) =~ "zdravo iz drugog procesa"
    end

    test "patching between channels loads their messages", %{conn: conn, user: user} do
      channel = channel_fixture(user, %{name: "drugi"})
      message_fixture(user, channel, %{body: "u drugom kanalu"})

      {:ok, view, _html} = live(conn, ~p"/c/general")
      refute render(view) =~ "u drugom kanalu"

      view |> element(~s{a[href="/c/drugi"]}) |> render_click()
      assert_patch(view, ~p"/c/drugi")
      assert render(view) =~ "u drugom kanalu"
    end

    test "sidebar shows initial unread counts", %{conn: conn, user: user} do
      other = user_fixture()
      channel = channel_fixture(other, %{name: "vruce"})
      {:ok, _} = Chat.join_channel(user, channel)
      message_fixture(other, channel, %{body: "nepročitano"})

      {:ok, view, _html} = live(conn, ~p"/c/general")
      assert has_element?(view, ~s{a[href="/c/vruce"] .cds-unread-badge}, "1")
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat_web/live/chat_live_test.exs`
Expected: FAIL — route `/c/:slug` does not exist / `ChatLive` undefined.

- [ ] **Step 3: Router** — in `lib/phoenix_chat_web/router.ex`:

1. DELETE the line `live "/", LobbyLive, :index` from the public scope (keep `live "/r/:room_id", RoomLive, :show` for now).
2. Inside the generated `live_session :require_authenticated_user ... do` block (the one holding the settings LiveViews), add:

```elixir
      live "/", ChatLive, :index
      live "/c/:slug", ChatLive, :channel
```

- [ ] **Step 4: Components** — create `lib/phoenix_chat_web/live/chat_live/components.ex`:

```elixir
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
    <div id={@id} class="cds-message">
      <.avatar username={@entry.username} />
      <div class="min-w-0 flex-1">
        <div class="cds-message-meta">
          <span class="cds-message-author">{@entry.username}</span>
          <span class="cds-message-time">{format_time(@entry.inserted_at)}</span>
        </div>
        <p class="cds-message-body">{@entry.body}</p>
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
end
```

(Times render in UTC — accepted MVP simplification.)

- [ ] **Step 5: LiveView** — create `lib/phoenix_chat_web/live/chat_live.ex`:

```elixir
defmodule PhoenixChatWeb.ChatLive do
  use PhoenixChatWeb, :live_view

  import PhoenixChatWeb.ChatComponents

  alias PhoenixChat.Chat

  @impl true
  def mount(_params, _session, socket) do
    user = current_user(socket)
    channels = Chat.list_joined_channels(user)
    dms = Chat.list_dm_channels(user)

    if connected?(socket) do
      for %{channel: channel} <- channels ++ dms, do: Chat.subscribe(channel)
    end

    {:ok,
     socket
     |> assign(
       channels: channels,
       dms: dms,
       active: nil,
       conversation_title: nil,
       newest: nil,
       older_cursor: nil,
       messages_empty?: true,
       form: empty_form()
     )
     |> stream(:messages, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    apply_action(socket, socket.assigns.live_action, params)
  end

  defp apply_action(socket, :index, _params) do
    {:noreply, push_patch(socket, to: ~p"/c/general")}
  end

  defp apply_action(socket, :channel, %{"slug" => slug}) do
    channel = Chat.get_channel_by_slug!(slug)
    {:noreply, open_conversation(socket, channel)}
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    case Chat.send_message(current_user(socket), socket.assigns.active, %{body: body}) do
      {:ok, _message} ->
        {:noreply, assign(socket, form: empty_form())}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :message))}

      {:error, :not_a_member} ->
        {:noreply, put_flash(socket, :error, gettext("You are not a member of this channel"))}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    %{active: active} = socket.assigns
    me = current_user(socket)

    if active && message.channel_id == active.id do
      Chat.mark_read(me, active)
      entry = build_entry(message, socket.assigns.newest, me.id)

      {:noreply,
       socket
       |> assign(newest: message, messages_empty?: false)
       |> stream_insert(:messages, entry)}
    else
      # Sidebar unread bump lands in Task 12.
      {:noreply, socket}
    end
  end

  # Reaction UI lands in Task 14; ignore the broadcast until then.
  def handle_info({:reaction_changed, _message}, socket), do: {:noreply, socket}

  ## Helpers

  defp open_conversation(socket, channel) do
    user = current_user(socket)
    Chat.mark_read(user, channel)
    {messages, older_cursor} = Chat.list_messages(channel)

    socket
    |> assign(
      active: channel,
      conversation_title: "#" <> channel.name,
      older_cursor: older_cursor,
      newest: List.last(messages),
      messages_empty?: messages == [],
      channels: clear_unread(socket.assigns.channels, channel.id),
      dms: clear_unread(socket.assigns.dms, channel.id),
      page_title: "#" <> channel.name,
      form: empty_form()
    )
    |> stream(:messages, build_entries(messages, user.id), reset: true)
  end

  defp build_entries(messages, me_id) do
    {entries, _prev} =
      Enum.map_reduce(messages, nil, fn message, prev ->
        {build_entry(message, prev, me_id), message}
      end)

    entries
  end

  # `prev` (the chronologically previous message) powers grouping in Task 11.
  defp build_entry(message, _prev, me_id) do
    %{
      id: message.id,
      user_id: message.user_id,
      username: message.user.username,
      body: message.body,
      inserted_at: message.inserted_at,
      reactions: Chat.summarize_reactions(message.reactions, me_id)
    }
  end

  defp clear_unread(rows, channel_id) do
    Enum.map(rows, fn
      %{channel: %{id: ^channel_id}} = row -> %{row | unread: 0}
      row -> row
    end)
  end

  defp empty_form, do: to_form(%{"body" => ""}, as: :message)

  defp current_user(socket), do: socket.assigns.current_scope.user
end
```

- [ ] **Step 6: Template** — create `lib/phoenix_chat_web/live/chat_live.html.heex`:

```heex
<div class="cds-shell">
  <aside class="cds-sidebar">
    <div class="cds-sidebar-header">
      <span class="w-4 h-4 bg-[#0f62fe]" aria-hidden="true"></span> PhoenixChat
    </div>

    <nav class="cds-sidebar-scroll">
      <div class="cds-section-label">{gettext("Channels")}</div>
      <.sidebar_item :for={row <- @channels} row={row} active_id={@active && @active.id} />
    </nav>

    <div class="cds-sidebar-user">
      <.avatar username={@current_scope.user.username} />
      <span class="truncate">{@current_scope.user.username}</span>
      <.link
        href={~p"/users/log-out"}
        method="delete"
        class="ml-auto text-[#0f62fe] hover:underline text-sm"
      >
        {gettext("Log out")}
      </.link>
    </div>
  </aside>

  <section class="cds-main">
    <%= if @active do %>
      <.channel_header title={@conversation_title} topic={@active.topic} />

      <div :if={@messages_empty?} class="cds-empty">
        {gettext("No messages yet — start the conversation.")}
      </div>

      <div id="message-list" class="cds-messages" phx-update="stream">
        <.message_entry :for={{dom_id, entry} <- @streams.messages} id={dom_id} entry={entry} />
      </div>

      <div class="cds-composer">
        <.form for={@form} id="composer" phx-submit="send_message" class="flex items-end gap-2">
          <div class="flex-1">
            <textarea
              id="composer-input"
              name={@form[:body].name}
              rows="2"
              class="cds-composer-input"
              placeholder={gettext("Message %{name}", name: @conversation_title)}
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
            <p
              :for={msg <- Enum.map(@form[:body].errors, &translate_error/1)}
              class="mt-1 text-sm text-[#da1e28]"
            >
              {msg}
            </p>
          </div>
          <button type="submit" class="cds-btn-primary">{gettext("Send")}</button>
        </.form>
      </div>
    <% end %>
  </section>
</div>

<Layouts.flash_group flash={@flash} />
```

- [ ] **Step 7: Chat CSS** — append to `assets/css/app.css` (end of file):

```css
/* === Chat shell (Carbon) === */
.cds-shell { display: flex; height: 100vh; overflow: hidden; background: #ffffff; }
.cds-sidebar { width: 260px; flex: none; display: flex; flex-direction: column; background: #f4f4f4; border-right: 1px solid #e0e0e0; }
.cds-sidebar-header { height: 48px; flex: none; display: flex; align-items: center; gap: 8px; padding: 0 16px; font-size: 16px; font-weight: 600; color: #161616; border-bottom: 1px solid #e0e0e0; }
.cds-sidebar-scroll { flex: 1; overflow-y: auto; padding: 16px 0; }
.cds-section-label { display: flex; align-items: center; justify-content: space-between; padding: 0 16px 4px; font-size: 12px; color: #525252; }
.cds-sidebar-item { display: flex; align-items: center; gap: 8px; padding: 6px 16px 6px 14px; border-left: 2px solid transparent; color: #161616; font-size: 14px; }
.cds-sidebar-item:hover { background: #e0e0e0; }
.cds-sidebar-item-active { background: #e0e0e0; border-left-color: #0f62fe; font-weight: 600; }
.cds-sidebar-hash { color: #8c8c8c; }
.cds-unread-badge { margin-left: auto; padding: 3px 6px; background: #161616; color: #ffffff; font-size: 12px; font-weight: 600; line-height: 1; }
.cds-sidebar-user { flex: none; display: flex; align-items: center; gap: 8px; padding: 12px 16px; border-top: 1px solid #e0e0e0; font-size: 14px; }
.cds-main { flex: 1; display: flex; flex-direction: column; min-width: 0; background: #ffffff; }
.cds-channel-header { height: 48px; flex: none; display: flex; align-items: center; gap: 12px; padding: 0 16px; border-bottom: 1px solid #e0e0e0; }
.cds-channel-name { font-size: 14px; font-weight: 600; color: #161616; white-space: nowrap; }
.cds-channel-topic { font-size: 14px; color: #525252; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.cds-messages { flex: 1; overflow-y: auto; padding: 16px 0; }
.cds-message { display: flex; gap: 12px; padding: 4px 16px; }
.cds-message:hover { background: #f4f4f4; }
.cds-avatar { width: 32px; height: 32px; flex: none; display: inline-flex; align-items: center; justify-content: center; background: #e0e0e0; color: #525252; font-size: 14px; font-weight: 600; }
.cds-message-meta { display: flex; align-items: baseline; gap: 8px; }
.cds-message-author { font-size: 14px; font-weight: 600; color: #161616; }
.cds-message-time { font-size: 12px; color: #8c8c8c; }
.cds-message-body { font-size: 14px; color: #161616; white-space: pre-wrap; overflow-wrap: anywhere; }
.cds-composer { flex: none; padding: 12px 16px 16px; border-top: 1px solid #e0e0e0; background: #ffffff; }
.cds-composer-input { width: 100%; background: #f4f4f4; border: none; border-bottom: 1px solid #e0e0e0; padding: 11px 16px; font-size: 14px; letter-spacing: 0.16px; color: #161616; resize: none; }
.cds-composer-input:focus { outline: none; border-bottom: 2px solid #0f62fe; padding-bottom: 10px; }
.cds-btn-primary { background: #0f62fe; color: #ffffff; border: none; padding: 12px 16px; font-size: 14px; cursor: pointer; }
.cds-btn-primary:hover { background: #0050e6; }
.cds-btn-primary:active { background: #002d9c; }
.cds-btn-tertiary { background: #ffffff; color: #0f62fe; border: 1px solid #0f62fe; padding: 11px 15px; font-size: 14px; cursor: pointer; }
.cds-btn-tertiary:hover { background: #f4f4f4; }
.cds-empty { padding: 32px 16px; text-align: center; font-size: 14px; color: #525252; }
```

- [ ] **Step 8: Delete the lobby and page controller**

```bash
rm lib/phoenix_chat_web/live/lobby_live.ex \
   lib/phoenix_chat_web/live/lobby_live.html.heex \
   test/phoenix_chat_web/live/lobby_live_test.exs \
   lib/phoenix_chat_web/controllers/page_controller.ex \
   lib/phoenix_chat_web/controllers/page_html.ex \
   test/phoenix_chat_web/controllers/page_controller_test.exs
rm -rf lib/phoenix_chat_web/controllers/page_html
```

- [ ] **Step 9: Run the full suite**

Run: `mix test`
Expected: PASS, `0 failures`. RoomLive tests still pass (its route is untouched). Compile must be warning-free: `mix compile --warnings-as-errors`.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "Add ChatLive shell with sidebar and realtime channel messaging" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Message list polish — grouping, day dividers, pagination, hooks

**Files:**
- Modify: `lib/phoenix_chat_web/live/chat_live.ex`, `lib/phoenix_chat_web/live/chat_live.html.heex`, `lib/phoenix_chat_web/live/chat_live/components.ex`, `assets/css/app.css`, `assets/js/app.js`
- Test: `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: T10 `build_entry/3` (`prev` param), `open_conversation/2`, stream `:messages`.
- Produces: entries gain `compact? :: boolean()` and `day_break? :: boolean()`; assigns gain `@oldest :: Message.t() | nil`; event `"load_older"`; JS hooks `ScrollToBottom` (on `#message-list`) and `ComposerKeys` (on `#composer-input`); button `#load-older`.

- [ ] **Step 1: Write failing tests** (append inside the `describe "channel view"` block):

```elixir
    test "groups consecutive same-author messages, day divider on first", %{
      conn: conn,
      user: user
    } do
      general = Chat.get_channel_by_slug!("general")
      message_fixture(user, general, %{body: "prva"})
      message_fixture(user, general, %{body: "druga"})
      other = user_fixture()
      message_fixture(other, general, %{body: "treca"})

      {:ok, view, _html} = live(conn, ~p"/c/general")

      assert has_element?(view, ".cds-message-compact", "druga")
      refute has_element?(view, ".cds-message-compact", "prva")
      refute has_element?(view, ".cds-message-compact", "treca")
      assert has_element?(view, ".cds-day-divider")
    end

    test "realtime messages group against the previous one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      view |> form("#composer", message: %{body: "brza jedan"}) |> render_submit()
      view |> form("#composer", message: %{body: "brza dva"}) |> render_submit()

      assert has_element?(view, ".cds-message-compact", "brza dva")
      refute has_element?(view, ".cds-message-compact", "brza jedan")
    end

    test "load older paginates past 50 messages", %{conn: conn, user: user} do
      general = Chat.get_channel_by_slug!("general")

      for i <- 1..55 do
        padded = String.pad_leading(Integer.to_string(i), 3, "0")
        message_fixture(user, general, %{body: "st-#{padded}"})
      end

      {:ok, view, _html} = live(conn, ~p"/c/general")

      refute render(view) =~ "st-005"
      assert render(view) =~ "st-006"
      assert has_element?(view, "#load-older")

      view |> element("#load-older") |> render_click()

      assert render(view) =~ "st-001"
      refute has_element?(view, "#load-older")
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat_web/live/chat_live_test.exs`
Expected: FAIL — no `.cds-message-compact`, no `#load-older`.

- [ ] **Step 3: Entry building with grouping** — in `lib/phoenix_chat_web/live/chat_live.ex`:

Add near the top of the module:

```elixir
  # Messages from the same author within this window collapse into one group.
  @compact_window_seconds 300
```

Replace `build_entry/3` with:

```elixir
  defp build_entry(message, prev, me_id) do
    same_day =
      prev != nil and
        DateTime.to_date(prev.inserted_at) == DateTime.to_date(message.inserted_at)

    compact? =
      same_day and prev.user_id == message.user_id and
        DateTime.diff(message.inserted_at, prev.inserted_at) < @compact_window_seconds

    %{
      id: message.id,
      user_id: message.user_id,
      username: message.user.username,
      body: message.body,
      inserted_at: message.inserted_at,
      compact?: compact?,
      day_break?: not same_day,
      reactions: Chat.summarize_reactions(message.reactions, me_id)
    }
  end
```

In `open_conversation/2`, add `oldest: List.first(messages),` to the `assign` keyword list (next to `newest:`), and add `oldest: nil,` to the mount assigns.

Add the pagination event handler (next to `"send_message"`):

```elixir
  def handle_event("load_older", _params, socket) do
    %{older_cursor: cursor, active: channel, oldest: boundary} = socket.assigns

    if cursor do
      me = current_user(socket)
      {older, next_cursor} = Chat.list_messages(channel, before_id: cursor)
      entries = build_entries(older, me.id)

      socket =
        entries
        |> Enum.with_index()
        |> Enum.reduce(socket, fn {entry, idx}, acc ->
          stream_insert(acc, :messages, entry, at: idx)
        end)

      # The old top message now has a predecessor — regroup it in place.
      socket =
        if boundary do
          rebuilt = build_entry(boundary, List.last(older), me.id)
          stream_insert(socket, :messages, rebuilt, at: length(entries))
        else
          socket
        end

      {:noreply,
       assign(socket,
         older_cursor: next_cursor,
         oldest: List.first(older) || boundary
       )}
    else
      {:noreply, socket}
    end
  end
```

- [ ] **Step 4: Component + template** — in `components.ex`, replace `message_entry/1` and add `format_date/1`:

```elixir
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

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y.")
```

In `chat_live.html.heex`: add the load-older button directly ABOVE the `#message-list` div (it must stay outside the stream container), and add the hooks:

```heex
      <button :if={@older_cursor} id="load-older" phx-click="load_older" class="cds-load-older">
        {gettext("Load older messages")}
      </button>

      <div id="message-list" class="cds-messages" phx-update="stream" phx-hook="ScrollToBottom">
```

and on the textarea add `phx-hook="ComposerKeys"`.

- [ ] **Step 5: CSS** — append to `assets/css/app.css`:

```css
.cds-message-wrap { }
.cds-day-divider { display: flex; align-items: center; gap: 12px; padding: 12px 16px 8px; }
.cds-day-divider::before, .cds-day-divider::after { content: ""; flex: 1; border-top: 1px solid #e0e0e0; }
.cds-day-divider-label { font-size: 12px; color: #8c8c8c; }
.cds-message-compact { padding-top: 0; padding-bottom: 0; }
.cds-message-gutter { width: 32px; flex: none; font-size: 12px; color: #8c8c8c; text-align: right; opacity: 0; padding-top: 3px; }
.cds-message:hover .cds-message-gutter { opacity: 1; }
.cds-load-older { display: block; margin: 8px auto 0; background: #ffffff; color: #0f62fe; border: none; font-size: 14px; padding: 8px 16px; cursor: pointer; }
.cds-load-older:hover { text-decoration: underline; }
```

- [ ] **Step 6: JS hooks** — in `assets/js/app.js`, add to the `Hooks` object (above `RoomRTC`):

```js
  ScrollToBottom: {
    mounted() {
      this.atBottom = true
      this.el.addEventListener("scroll", () => {
        this.atBottom = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 40
      })
      this.scrollDown()
    },
    updated() { if (this.atBottom) this.scrollDown() },
    scrollDown() { this.el.scrollTop = this.el.scrollHeight }
  },

  ComposerKeys: {
    mounted() {
      this.el.addEventListener("keydown", e => {
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault()
          const form = this.el.closest("form")
          if (form) form.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}))
        }
      })
    }
  },
```

- [ ] **Step 7: Run tests**

Run: `mix test`
Expected: PASS, `0 failures`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Group messages, add day dividers, pagination and composer hooks" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Live unread badges

**Files:**
- Modify: `lib/phoenix_chat_web/live/chat_live.ex`
- Test: `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: T10 `handle_info({:new_message, ...})`, `clear_unread/2`, sidebar badge markup.
- Produces: messages arriving in inactive conversations increment that row's badge live, except the current user's own messages; opening a conversation still clears its badge.

- [ ] **Step 1: Write failing tests** (append inside `describe "channel view"`):

```elixir
    test "bumps unread badge for inactive-channel messages, clears on open", %{
      conn: conn,
      user: user
    } do
      other = user_fixture()
      channel = channel_fixture(other, %{name: "sporedni"})
      {:ok, _} = Chat.join_channel(user, channel)

      {:ok, view, _html} = live(conn, ~p"/c/general")
      refute has_element?(view, ~s{a[href="/c/sporedni"] .cds-unread-badge})

      {:ok, _} = Chat.send_message(other, channel, %{body: "pssst"})
      assert has_element?(view, ~s{a[href="/c/sporedni"] .cds-unread-badge}, "1")

      {:ok, _} = Chat.send_message(other, channel, %{body: "opet"})
      assert has_element?(view, ~s{a[href="/c/sporedni"] .cds-unread-badge}, "2")

      view |> element(~s{a[href="/c/sporedni"]}) |> render_click()
      refute has_element?(view, ~s{a[href="/c/sporedni"] .cds-unread-badge})
    end

    test "own messages in another channel don't bump my badge", %{conn: conn, user: user} do
      channel = channel_fixture(user, %{name: "moj-kanal"})

      {:ok, view, _html} = live(conn, ~p"/c/general")
      {:ok, _} = Chat.send_message(user, channel, %{body: "sam sa sobom"})

      refute has_element?(view, ~s{a[href="/c/moj-kanal"] .cds-unread-badge})
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat_web/live/chat_live_test.exs`
Expected: FAIL — badge never appears (T10 ignores inactive-channel messages).

- [ ] **Step 3: Implement** — in `chat_live.ex`, replace the body of `handle_info({:new_message, message}, socket)` with:

```elixir
    %{active: active} = socket.assigns
    me = current_user(socket)

    cond do
      active && message.channel_id == active.id ->
        Chat.mark_read(me, active)
        entry = build_entry(message, socket.assigns.newest, me.id)

        {:noreply,
         socket
         |> assign(newest: message, messages_empty?: false)
         |> stream_insert(:messages, entry)}

      message.user_id == me.id ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> update(:channels, &bump_unread(&1, message.channel_id))
         |> update(:dms, &bump_unread(&1, message.channel_id))}
    end
```

Add the helper next to `clear_unread/2`:

```elixir
  defp bump_unread(rows, channel_id) do
    Enum.map(rows, fn
      %{channel: %{id: ^channel_id}} = row -> %{row | unread: row.unread + 1}
      row -> row
    end)
  end
```

- [ ] **Step 4: Run tests**

Run: `mix test`
Expected: PASS, `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Update sidebar unread badges in real time" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 13: DMs in the UI + presence dots

**Files:**
- Modify: `lib/phoenix_chat/accounts.ex` (`get_user_by_username!/1`, `list_users_except/1`), `lib/phoenix_chat_web/router.ex`, `lib/phoenix_chat_web/live/chat_live.ex`, `lib/phoenix_chat_web/live/chat_live.html.heex`, `lib/phoenix_chat_web/live/chat_live/components.ex`, `assets/css/app.css`
- Test: `test/phoenix_chat/accounts_test.exs`, `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: `Chat.get_or_create_dm!/2`, `dm_other_user/2`, `list_dm_channels/1` (T5); `ChatComponents` (T10).
- Produces:
  - Route `/dm/:username` → `ChatLive, :dm`
  - `Accounts.get_user_by_username!(username) :: User.t()` (raises), `Accounts.list_users_except(user) :: [User.t()]` (username asc)
  - Assigns: `@online :: MapSet.t(String.t())` (user ids as strings), `@show_dm_modal`, `@dm_candidates`
  - Components: `dm_item/1` (attrs `row`, `active_id`, `online`), `cds_modal/1` (attrs `id`, `show`, `title`, `on_cancel` event-name string; slot `inner_block`)
  - Presence topic `"presence:online"`, key `to_string(user.id)`, meta `%{username: username}`
  - `open_conversation/2` now derives `@conversation_title` (`"#name"` / `"@username"`) and closes the DM modal
  - Test helper `eventually/1` in `chat_live_test.exs`

- [ ] **Step 1: Write failing tests**

Append to `test/phoenix_chat/accounts_test.exs`:

```elixir
    test "get_user_by_username!/1 raises for unknown username" do
      user = user_fixture()
      assert Accounts.get_user_by_username!(user.username).id == user.id
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user_by_username!("niko") end
    end

    test "list_users_except/1 lists everyone else, username asc" do
      me = user_fixture()
      a = user_fixture()
      b = user_fixture()

      usernames = Accounts.list_users_except(me) |> Enum.map(& &1.username)
      assert Enum.sort([a.username, b.username]) == usernames
      refute me.username in usernames
    end
```

Append a new describe block to `test/phoenix_chat_web/live/chat_live_test.exs`:

```elixir
  describe "direct messages & presence" do
    setup :register_and_log_in_user

    test "/dm/:username opens (and creates) the DM", %{conn: conn} do
      other = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/dm/#{other.username}")
      assert has_element?(view, ".cds-channel-name", "@#{other.username}")

      view |> form("#composer", message: %{body: "zdravo nasamo"}) |> render_submit()
      assert has_element?(view, "#message-list", "zdravo nasamo")
    end

    test "DM messages arrive in real time", %{conn: conn, user: user} do
      other = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/dm/#{other.username}")

      dm = PhoenixChat.Chat.get_or_create_dm!(user, other)
      {:ok, _} = Chat.send_message(other, dm, %{body: "odgovor"})

      assert render(view) =~ "odgovor"
    end

    test "unknown username 404s", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/dm/niko-nepoznat") end
    end

    test "self-DM redirects to general with an error", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dm/#{user.username}")
      assert_patch(view, ~p"/c/general")
      assert render(view) =~ "You cannot message yourself"
    end

    test "existing DM shows in sidebar with unread bump", %{conn: conn, user: user} do
      other = user_fixture()
      dm = Chat.get_or_create_dm!(user, other)

      {:ok, view, _html} = live(conn, ~p"/c/general")
      assert has_element?(view, ~s{a[href="/dm/#{other.username}"]})

      {:ok, _} = Chat.send_message(other, dm, %{body: "javi se"})
      assert has_element?(view, ~s{a[href="/dm/#{other.username}"] .cds-unread-badge}, "1")
    end

    test "online dot appears when the other user connects", %{conn: conn, user: user} do
      other = user_fixture()
      Chat.get_or_create_dm!(user, other)

      {:ok, view, _html} = live(conn, ~p"/c/general")
      refute has_element?(view, ".cds-presence-dot-online")

      other_conn = Phoenix.ConnTest.build_conn() |> log_in_user(other)
      {:ok, _other_view, _html} = live(other_conn, ~p"/c/general")

      eventually(fn -> has_element?(view, ".cds-presence-dot-online") end)
    end

    test "new-DM modal lists users and links to them", %{conn: conn} do
      other = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/c/general")

      view |> element("#open-dm-modal") |> render_click()
      assert has_element?(view, "#dm-modal .cds-user-row", other.username)
    end
  end
```

And this private helper at the bottom of the test module (used by the presence test):

```elixir
  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition not met within retries")
      true ->
        Process.sleep(10)
        eventually(fun, tries - 1)
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat_web/live/chat_live_test.exs test/phoenix_chat/accounts_test.exs`
Expected: FAIL — no `/dm/:username` route, `get_user_by_username!/1` undefined.

- [ ] **Step 3: Accounts additions** — in `lib/phoenix_chat/accounts.ex`, next to `get_user_by_username/1`:

```elixir
  def get_user_by_username!(username) when is_binary(username) do
    Repo.get_by!(User, username: username)
  end

  @doc "All users except the given one, for the new-DM picker."
  def list_users_except(%User{id: id}) do
    Repo.all(from u in User, where: u.id != ^id, order_by: [asc: u.username])
  end
```

(Ensure `import Ecto.Query, warn: false` is present at the top — the generated Accounts module already has it.)

- [ ] **Step 4: Route** — in the same `live_session :require_authenticated_user` block:

```elixir
      live "/dm/:username", ChatLive, :dm
```

- [ ] **Step 5: ChatLive changes** — in `lib/phoenix_chat_web/live/chat_live.ex`:

Add near the aliases:

```elixir
  alias PhoenixChat.Accounts
  alias PhoenixChatWeb.Presence

  @online_topic "presence:online"
```

In `mount/3`, inside the `if connected?(socket) do` block, after the subscribe loop:

```elixir
      {:ok, _} =
        Presence.track(self(), @online_topic, to_string(user.id), %{username: user.username})

      Phoenix.PubSub.subscribe(PhoenixChat.PubSub, @online_topic)
```

Extend the mount assigns with:

```elixir
       online: online_ids(),
       show_dm_modal: false,
       dm_candidates: [],
```

Add the `:dm` action clause (after the `:channel` clause):

```elixir
  defp apply_action(socket, :dm, %{"username" => username}) do
    me = current_user(socket)
    other = Accounts.get_user_by_username!(username)

    if other.id == me.id do
      {:noreply,
       socket
       |> put_flash(:error, gettext("You cannot message yourself"))
       |> push_patch(to: ~p"/c/general")}
    else
      channel = Chat.get_or_create_dm!(me, other)

      {:noreply,
       socket
       |> ensure_dm_row(channel, other)
       |> open_conversation(channel)}
    end
  end

  defp ensure_dm_row(socket, channel, other) do
    if Enum.any?(socket.assigns.dms, &(&1.channel.id == channel.id)) do
      socket
    else
      if connected?(socket), do: Chat.subscribe(channel)
      update(socket, :dms, &(&1 ++ [%{channel: channel, other_user: other, unread: 0}]))
    end
  end
```

In `open_conversation/2`, replace the two hardcoded `"#" <> channel.name` values with a computed title, and close the DM modal. The top of the function becomes:

```elixir
  defp open_conversation(socket, channel) do
    user = current_user(socket)
    title = conversation_title(channel, user)
    Chat.mark_read(user, channel)
    {messages, older_cursor} = Chat.list_messages(channel)
```

with `conversation_title: title,` / `page_title: title,` / `show_dm_modal: false,` in its assign list, and this helper below it:

```elixir
  defp conversation_title(%{kind: :dm} = channel, me),
    do: "@" <> Chat.dm_other_user(channel, me).username

  defp conversation_title(channel, _me), do: "#" <> channel.name
```

Presence + modal handlers:

```elixir
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, online: online_ids())}
  end
```

(place it with the other `handle_info` clauses; keep `@impl true` only on the first clause of the group)

```elixir
  def handle_event("open_dm_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_dm_modal: true,
       dm_candidates: Accounts.list_users_except(current_user(socket))
     )}
  end

  def handle_event("close_dm_modal", _params, socket) do
    {:noreply, assign(socket, show_dm_modal: false)}
  end
```

```elixir
  defp online_ids do
    Presence.list(@online_topic) |> Map.keys() |> MapSet.new()
  end
```

- [ ] **Step 6: Components** — add to `lib/phoenix_chat_web/live/chat_live/components.ex`:

```elixir
  attr :row, :map, required: true, doc: "%{channel:, other_user:, unread:}"
  attr :active_id, :any, default: nil
  attr :online, :any, required: true, doc: "MapSet of online user ids (strings)"

  def dm_item(assigns) do
    ~H"""
    <.link
      patch={~p"/dm/#{@row.other_user.username}"}
      class={[
        "cds-sidebar-item",
        @active_id == @row.channel.id && "cds-sidebar-item-active"
      ]}
    >
      <span
        class={[
          "cds-presence-dot",
          MapSet.member?(@online, to_string(@row.other_user.id)) && "cds-presence-dot-online"
        ]}
        aria-hidden="true"
      >
      </span>
      <span class="truncate">{@row.other_user.username}</span>
      <span :if={@row.unread > 0} class="cds-unread-badge">{@row.unread}</span>
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, required: true
  attr :on_cancel, :string, required: true, doc: "event name pushed on close"
  slot :inner_block, required: true

  def cds_modal(assigns) do
    ~H"""
    <div :if={@show} id={@id} class="cds-modal-overlay">
      <div class="cds-modal" phx-click-away={JS.push(@on_cancel)}>
        <div class="cds-modal-header">
          <h2 class="cds-modal-title">{@title}</h2>
          <button phx-click={@on_cancel} class="cds-modal-close" aria-label={gettext("Close")}>
            ✕
          </button>
        </div>
        <div class="cds-modal-body">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 7: Template** — in `chat_live.html.heex`:

Below the Channels section in `<nav class="cds-sidebar-scroll">`, add:

```heex
      <div class="cds-section-label mt-4">
        {gettext("Direct messages")}
        <button
          id="open-dm-modal"
          phx-click="open_dm_modal"
          class="cds-icon-btn"
          aria-label={gettext("New direct message")}
        >
          +
        </button>
      </div>
      <.dm_item :for={row <- @dms} row={row} active_id={@active && @active.id} online={@online} />
```

At the bottom of the file (after `<Layouts.flash_group ... />`):

```heex
<.cds_modal
  id="dm-modal"
  show={@show_dm_modal}
  title={gettext("New direct message")}
  on_cancel="close_dm_modal"
>
  <div :if={@dm_candidates == []} class="cds-empty">{gettext("No other users yet.")}</div>
  <.link
    :for={user <- @dm_candidates}
    patch={~p"/dm/#{user.username}"}
    class="cds-user-row"
  >
    <.avatar username={user.username} />
    <span class="truncate">{user.username}</span>
  </.link>
</.cds_modal>
```

- [ ] **Step 8: CSS** — append to `assets/css/app.css`:

```css
.cds-presence-dot { width: 8px; height: 8px; flex: none; background: #ffffff; border: 1px solid #8c8c8c; }
.cds-presence-dot-online { background: #24a148; border-color: #24a148; }
.cds-icon-btn { background: none; border: none; padding: 0 4px; color: #0f62fe; font-size: 14px; cursor: pointer; }
.cds-modal-overlay { position: fixed; inset: 0; z-index: 50; display: flex; align-items: flex-start; justify-content: center; padding-top: 96px; background: rgba(22, 22, 22, 0.5); }
.cds-modal { width: 100%; max-width: 480px; background: #ffffff; border: 1px solid #161616; }
.cds-modal-header { display: flex; align-items: center; justify-content: space-between; padding: 16px; border-bottom: 1px solid #e0e0e0; }
.cds-modal-title { font-size: 20px; font-weight: 400; color: #161616; }
.cds-modal-close { background: none; border: none; padding: 4px; color: #525252; font-size: 14px; cursor: pointer; }
.cds-modal-body { padding: 16px; max-height: 60vh; overflow-y: auto; }
.cds-user-row { display: flex; align-items: center; gap: 8px; width: 100%; padding: 8px; font-size: 14px; color: #161616; }
.cds-user-row:hover { background: #f4f4f4; }
```

- [ ] **Step 9: Run tests**

Run: `mix test`
Expected: PASS, `0 failures`.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "Add DM conversations, new-DM modal and online presence dots" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 14: Reactions UI

**Files:**
- Modify: `lib/phoenix_chat_web/live/chat_live.ex`, `lib/phoenix_chat_web/live/chat_live.html.heex`, `lib/phoenix_chat_web/live/chat_live/components.ex`, `assets/css/app.css`
- Test: `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: `Chat.toggle_reaction/3`, `reaction_palette/0`, `get_message!/1`, `summarize_reactions/2` (T8); entry `reactions` field (T10).
- Produces: assigns `@palette_for :: integer() | nil`, `@entry_meta :: %{message_id => %{compact?: boolean(), day_break?: boolean()}}`; events `"toggle_reaction"`, `"open_palette"`, `"pick_reaction"`; helper `insert_entry/3` (stream insert + meta bookkeeping); `message_entry/1` gains `palette_for` attr and renders reaction chips + palette popover.

- [ ] **Step 1: Write failing tests** (append inside `describe "channel view"`):

```elixir
    test "reactions toggle and update in real time", %{conn: conn, user: user} do
      general = Chat.get_channel_by_slug!("general")
      message = message_fixture(user, general, %{body: "reaguj na ovo"})

      {:ok, view, _html} = live(conn, ~p"/c/general")

      view |> element(".cds-reaction-add") |> render_click()
      view |> element(".cds-palette-item", "👍") |> render_click()

      assert has_element?(view, ".cds-reaction-chip-mine", "1")

      other = user_fixture()
      :ok = Chat.toggle_reaction(other, message, "👍")
      assert has_element?(view, ".cds-reaction-chip", "2")

      view |> element(".cds-reaction-chip-mine") |> render_click()
      assert has_element?(view, ".cds-reaction-chip", "1")
      refute has_element?(view, ".cds-reaction-chip-mine")
    end

    test "reaction updates keep message grouping intact", %{conn: conn, user: user} do
      general = Chat.get_channel_by_slug!("general")
      message_fixture(user, general, %{body: "prva u grupi"})
      compact = message_fixture(user, general, %{body: "druga u grupi"})

      {:ok, view, _html} = live(conn, ~p"/c/general")
      assert has_element?(view, ".cds-message-compact", "druga u grupi")

      other = user_fixture()
      :ok = Chat.toggle_reaction(other, compact, "🔥")

      assert has_element?(view, ".cds-reaction-chip", "1")
      assert has_element?(view, ".cds-message-compact", "druga u grupi")
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat_web/live/chat_live_test.exs`
Expected: FAIL — no `.cds-reaction-add` element.

- [ ] **Step 3: Entry-meta bookkeeping** — in `chat_live.ex`:

Add to mount assigns: `palette_for: nil, entry_meta: %{},`

Add the helper (near `build_entries/2`):

```elixir
  # Streams can't be read back; remember each entry's layout flags so
  # reaction updates can re-insert without breaking grouping.
  defp insert_entry(socket, entry, opts \\ []) do
    socket
    |> update(:entry_meta, &Map.put(&1, entry.id, %{compact?: entry.compact?, day_break?: entry.day_break?}))
    |> stream_insert(:messages, entry, opts)
  end
```

Route every message insert through it:
1. In `open_conversation/2`: add `entry_meta: Map.new(entries, &{&1.id, %{compact?: &1.compact?, day_break?: &1.day_break?}}),` to the assign list, binding `entries = build_entries(messages, user.id)` before the assign and passing `entries` to the existing `stream(:messages, entries, reset: true)`. Also add `palette_for: nil,` there.
2. In `handle_info({:new_message, ...})` active branch: replace `stream_insert(:messages, entry)` with `insert_entry(entry)` — i.e. the pipe becomes:

```elixir
        {:noreply,
         socket
         |> assign(newest: message, messages_empty?: false)
         |> insert_entry(entry)}
```

3. In `handle_event("load_older", ...)`: replace both `stream_insert(acc, :messages, entry, at: idx)` with `insert_entry(acc, entry, at: idx)` and `stream_insert(socket, :messages, rebuilt, at: length(entries))` with `insert_entry(socket, rebuilt, at: length(entries))`.

Replace the `handle_info({:reaction_changed, _message}, ...)` stub with:

```elixir
  def handle_info({:reaction_changed, message}, socket) do
    %{active: active, entry_meta: entry_meta} = socket.assigns

    if active && message.channel_id == active.id do
      me = current_user(socket)
      meta = Map.get(entry_meta, message.id, %{compact?: false, day_break?: false})

      rebuilt = %{
        id: message.id,
        user_id: message.user_id,
        username: message.user.username,
        body: message.body,
        inserted_at: message.inserted_at,
        compact?: meta.compact?,
        day_break?: meta.day_break?,
        reactions: Chat.summarize_reactions(message.reactions, me.id)
      }

      {:noreply, stream_insert(socket, :messages, rebuilt)}
    else
      {:noreply, socket}
    end
  end
```

Add the events:

```elixir
  def handle_event("toggle_reaction", %{"message-id" => id, "emoji" => emoji}, socket) do
    message = Chat.get_message!(id)
    _ = Chat.toggle_reaction(current_user(socket), message, emoji)
    {:noreply, socket}
  end

  def handle_event("open_palette", %{"message-id" => id}, socket) do
    id = String.to_integer(id)
    palette_for = if socket.assigns.palette_for == id, do: nil, else: id
    {:noreply, assign(socket, palette_for: palette_for)}
  end

  def handle_event("pick_reaction", params, socket) do
    {:noreply, socket} = handle_event("toggle_reaction", params, socket)
    {:noreply, assign(socket, palette_for: nil)}
  end
```

- [ ] **Step 4: Component** — in `components.ex`, add `attr :palette_for, :any, default: nil` to `message_entry/1` and insert this block directly under the `<p class="cds-message-body">...</p>` line:

```heex
        <div class="cds-reactions">
          <button
            :for={r <- @entry.reactions}
            phx-click="toggle_reaction"
            phx-value-message-id={@entry.id}
            phx-value-emoji={r.emoji}
            class={["cds-reaction-chip", r.mine && "cds-reaction-chip-mine"]}
          >
            <span>{r.emoji}</span>
            <span class="cds-reaction-count">{r.count}</span>
          </button>
          <button
            phx-click="open_palette"
            phx-value-message-id={@entry.id}
            class="cds-reaction-add"
            aria-label={gettext("Add reaction")}
          >
            +
          </button>
          <div :if={@palette_for == @entry.id} class="cds-palette">
            <button
              :for={emoji <- PhoenixChat.Chat.reaction_palette()}
              phx-click="pick_reaction"
              phx-value-message-id={@entry.id}
              phx-value-emoji={emoji}
              class="cds-palette-item"
            >
              {emoji}
            </button>
          </div>
        </div>
```

In `chat_live.html.heex`, pass the assign through:

```heex
        <.message_entry
          :for={{dom_id, entry} <- @streams.messages}
          id={dom_id}
          entry={entry}
          palette_for={@palette_for}
        />
```

- [ ] **Step 5: CSS** — append to `assets/css/app.css`:

```css
.cds-reactions { position: relative; display: flex; flex-wrap: wrap; gap: 4px; margin-top: 4px; }
.cds-reactions:empty { display: none; }
.cds-reaction-chip { display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px; background: #ffffff; border: 1px solid #e0e0e0; font-size: 12px; color: #161616; cursor: pointer; }
.cds-reaction-chip:hover { border-color: #8c8c8c; }
.cds-reaction-chip-mine { border-color: #0f62fe; color: #0f62fe; }
.cds-reaction-count { font-weight: 600; }
.cds-reaction-add { display: inline-flex; align-items: center; padding: 2px 8px; background: #ffffff; border: 1px solid #e0e0e0; font-size: 12px; color: #525252; cursor: pointer; opacity: 0; }
.cds-message:hover .cds-reaction-add, .cds-reaction-add:focus { opacity: 1; }
.cds-palette { position: absolute; bottom: 100%; left: 0; z-index: 10; display: flex; gap: 2px; padding: 4px; background: #ffffff; border: 1px solid #161616; }
.cds-palette-item { background: none; border: none; padding: 4px 6px; font-size: 16px; cursor: pointer; }
.cds-palette-item:hover { background: #f4f4f4; }
```

- [ ] **Step 6: Run tests**

Run: `mix test`
Expected: PASS, `0 failures`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add reaction chips with palette popover" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 15: Create/browse channels + join gate

**Files:**
- Modify: `lib/phoenix_chat_web/live/chat_live.ex`, `lib/phoenix_chat_web/live/chat_live.html.heex`
- Test: `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: `Chat.create_channel/2`, `list_browsable_channels/1`, `join_channel/2`, `member?/2` (T3); `cds_modal/1` (T13); `Channel.create_changeset/2` (T3).
- Produces: assigns `@gate? :: boolean()`, `@show_create_modal`, `@show_browse_modal`, `@browsable`, `@create_form`; events `"open_create_modal"`, `"close_create_modal"`, `"create_channel"`, `"open_browse_modal"`, `"close_browse_modal"`, `"join_channel"` (value `channel-id`), `"join_gated"`; visiting a not-joined public channel renders a join interstitial instead of messages; foreign DM slugs 404.

- [ ] **Step 1: Write failing tests** (new describe block in `chat_live_test.exs`):

```elixir
  describe "channel management" do
    setup :register_and_log_in_user

    test "creates a channel from the modal and navigates to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      view |> element("#open-create-modal") |> render_click()

      html =
        view
        |> form("#create-channel-form", channel: %{name: "X", topic: ""})
        |> render_submit()

      assert html =~ "should be at least 2 character(s)"

      view
      |> form("#create-channel-form", channel: %{name: "Novi-Kanal", topic: "tema"})
      |> render_submit()

      assert_patch(view, ~p"/c/novi-kanal")
      assert has_element?(view, ".cds-channel-name", "#novi-kanal")
      assert has_element?(view, ~s{a[href="/c/novi-kanal"]})
    end

    test "browse modal lists unjoined channels and joins them", %{conn: conn} do
      other = user_fixture()
      channel_fixture(other, %{name: "tudji-kanal"})

      {:ok, view, _html} = live(conn, ~p"/c/general")
      refute has_element?(view, ~s{a[href="/c/tudji-kanal"]})

      view |> element("#open-browse-modal") |> render_click()
      assert has_element?(view, "#browse-modal", "tudji-kanal")

      view |> element(~s{#browse-modal button[phx-click="join_channel"]}) |> render_click()

      assert_patch(view, ~p"/c/tudji-kanal")
      assert has_element?(view, ~s{a[href="/c/tudji-kanal"]})
    end

    test "not-joined channel URL shows a join gate", %{conn: conn, user: user} do
      other = user_fixture()
      channel = channel_fixture(other, %{name: "zatvoren"})
      message_fixture(other, channel, %{body: "tajna poruka"})

      {:ok, view, _html} = live(conn, ~p"/c/zatvoren")

      assert has_element?(view, "#join-gate")
      refute render(view) =~ "tajna poruka"
      refute has_element?(view, "#composer")

      view |> element("#join-gate button") |> render_click()

      refute has_element?(view, "#join-gate")
      assert render(view) =~ "tajna poruka"
      assert PhoenixChat.Chat.member?(user, channel)
    end

    test "foreign DM slug 404s", %{conn: conn} do
      a = user_fixture()
      b = user_fixture()
      dm = Chat.get_or_create_dm!(a, b)

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/c/#{dm.slug}") end
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat_web/live/chat_live_test.exs`
Expected: FAIL — no `#open-create-modal`; gated channel currently renders messages.

- [ ] **Step 3: ChatLive** — in `chat_live.ex`:

Add aliases + mount assigns:

```elixir
  alias PhoenixChat.Chat.Channel
```

mount assigns add: `gate?: false, show_create_modal: false, show_browse_modal: false, browsable: [], create_form: new_create_form(),`

Helper:

```elixir
  defp new_create_form do
    to_form(Channel.create_changeset(%Channel{kind: :channel}, %{}), as: :channel)
  end
```

Replace `apply_action(socket, :channel, %{"slug" => slug})` with:

```elixir
  defp apply_action(socket, :channel, %{"slug" => slug}) do
    channel = Chat.get_channel_by_slug!(slug)
    me = current_user(socket)

    cond do
      Chat.member?(me, channel) ->
        {:noreply, open_conversation(socket, channel)}

      channel.kind == :dm ->
        # Behave as if it doesn't exist — DMs are private.
        raise Ecto.NoResultsError, queryable: Channel

      true ->
        {:noreply,
         socket
         |> assign(
           active: channel,
           gate?: true,
           conversation_title: "#" <> channel.name,
           page_title: "#" <> channel.name,
           messages_empty?: true,
           older_cursor: nil,
           newest: nil,
           oldest: nil,
           entry_meta: %{},
           palette_for: nil
         )
         |> stream(:messages, [], reset: true)}
    end
  end
```

In `open_conversation/2` assigns, add `gate?: false,`.

Modal + join events:

```elixir
  def handle_event("open_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: true, create_form: new_create_form())}
  end

  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: false)}
  end

  def handle_event("create_channel", %{"channel" => attrs}, socket) do
    case Chat.create_channel(current_user(socket), attrs) do
      {:ok, channel} ->
        if connected?(socket), do: Chat.subscribe(channel)

        {:noreply,
         socket
         |> assign(
           channels: Chat.list_joined_channels(current_user(socket)),
           show_create_modal: false
         )
         |> push_patch(to: ~p"/c/#{channel.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, create_form: to_form(changeset, as: :channel))}
    end
  end

  def handle_event("open_browse_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_browse_modal: true,
       browsable: Chat.list_browsable_channels(current_user(socket))
     )}
  end

  def handle_event("close_browse_modal", _params, socket) do
    {:noreply, assign(socket, show_browse_modal: false)}
  end

  def handle_event("join_channel", %{"channel-id" => id}, socket) do
    me = current_user(socket)
    channel = Chat.get_channel!(id)
    {:ok, _} = Chat.join_channel(me, channel)
    if connected?(socket), do: Chat.subscribe(channel)

    {:noreply,
     socket
     |> assign(channels: Chat.list_joined_channels(me), show_browse_modal: false)
     |> push_patch(to: ~p"/c/#{channel.slug}")}
  end

  def handle_event("join_gated", _params, socket) do
    me = current_user(socket)
    channel = socket.assigns.active
    {:ok, _} = Chat.join_channel(me, channel)
    if connected?(socket), do: Chat.subscribe(channel)

    {:noreply,
     socket
     |> assign(channels: Chat.list_joined_channels(me))
     |> open_conversation(channel)}
  end
```

- [ ] **Step 4: Template** — in `chat_live.html.heex`:

Give the Channels section label its buttons (replace the plain label div):

```heex
      <div class="cds-section-label">
        {gettext("Channels")}
        <span>
          <button
            id="open-browse-modal"
            phx-click="open_browse_modal"
            class="cds-icon-btn"
            aria-label={gettext("Browse channels")}
          >
            ⌕
          </button>
          <button
            id="open-create-modal"
            phx-click="open_create_modal"
            class="cds-icon-btn"
            aria-label={gettext("Create channel")}
          >
            +
          </button>
        </span>
      </div>
```

Wrap the main conversation area in the gate branch — the `<%= if @active do %>` body becomes:

```heex
      <.channel_header title={@conversation_title} topic={@active.topic} />

      <%= if @gate? do %>
        <div id="join-gate" class="cds-empty">
          <p class="mb-4">
            {gettext("You are not a member of %{name} yet.", name: @conversation_title)}
          </p>
          <button phx-click="join_gated" class="cds-btn-primary">{gettext("Join channel")}</button>
        </div>
      <% else %>
        <button :if={@older_cursor} id="load-older" phx-click="load_older" class="cds-load-older">
          {gettext("Load older messages")}
        </button>

        <div :if={@messages_empty?} class="cds-empty">
          {gettext("No messages yet — start the conversation.")}
        </div>

        <div id="message-list" class="cds-messages" phx-update="stream" phx-hook="ScrollToBottom">
          <.message_entry
            :for={{dom_id, entry} <- @streams.messages}
            id={dom_id}
            entry={entry}
            palette_for={@palette_for}
          />
        </div>

        <div class="cds-composer">
          <!-- existing composer form unchanged -->
        </div>
      <% end %>
```

(Keep the existing composer form markup — only its position moves inside the `<%= else %>` branch.)

Add both modals at the bottom (next to the DM modal):

```heex
<.cds_modal
  id="create-modal"
  show={@show_create_modal}
  title={gettext("Create channel")}
  on_cancel="close_create_modal"
>
  <.form for={@create_form} id="create-channel-form" phx-submit="create_channel" class="space-y-2">
    <.input
      field={@create_form[:name]}
      type="text"
      label={gettext("Name")}
      placeholder={gettext("e.g. marketing")}
    />
    <.input field={@create_form[:topic]} type="text" label={gettext("Topic (optional)")} />
    <button type="submit" class="cds-btn-primary w-full">{gettext("Create")}</button>
  </.form>
</.cds_modal>

<.cds_modal
  id="browse-modal"
  show={@show_browse_modal}
  title={gettext("Browse channels")}
  on_cancel="close_browse_modal"
>
  <div :if={@browsable == []} class="cds-empty">{gettext("No channels to join.")}</div>
  <div :for={channel <- @browsable} class="cds-user-row">
    <span class="cds-sidebar-hash">#</span>
    <span class="truncate flex-1">{channel.name}</span>
    <button
      phx-click="join_channel"
      phx-value-channel-id={channel.id}
      class="cds-btn-tertiary"
    >
      {gettext("Join")}
    </button>
  </div>
</.cds_modal>
```

- [ ] **Step 5: Run tests**

Run: `mix test`
Expected: PASS, `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add channel create/browse modals and membership join gate" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 16: Huddle — auth'd video rooms per channel

Existing WebRTC machinery (`RoomChannel`, `RoomRTC` hook) stays untouched. `RoomLive` moves under auth at `/huddle/:slug`, keyed by channel slug, membership-gated, identity = username; the template gets the Carbon dark-stage treatment. The lobby-era `?dn=` flow and `/r/:room_id` route die.

**Files:**
- Modify: `lib/phoenix_chat_web/router.ex`, `lib/phoenix_chat_web/live/room_live.ex`, `lib/phoenix_chat_web/live/room_live.html.heex` (full rewrite), `lib/phoenix_chat_web/live/chat_live.html.heex` (header huddle link), `assets/css/app.css` (replace PoC section with huddle styles)
- Test: `test/phoenix_chat_web/live/room_live_test.exs` (full rewrite), `test/phoenix_chat_web/live/chat_live_test.exs` (header link)

**Interfaces:**
- Consumes: `Chat.get_channel_by_slug!/1`, `member?/2` (T3); `current_scope` (T1); `channel_header/1` `:actions` slot (T10).
- Produces: route `/huddle/:slug` in the authenticated live_session; `#huddle-link` anchor in the channel header; RoomLive assigns unchanged in shape (`room_id` = slug, `display_name` = username) so `RoomRTC` and `RoomChannel` keep working; DOM ids preserved: `rtc-root, video-grid, local-video, screen-video, controls-bar, btn-mic, btn-cam, btn-share, sel-mic, sel-cam, device-form, chat-panel, messages, chat-form, participants`.

- [ ] **Step 1: Rewrite the RoomLive tests** — replace `test/phoenix_chat_web/live/room_live_test.exs` with:

```elixir
defmodule PhoenixChatWeb.RoomLiveTest do
  use PhoenixChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PhoenixChat.AccountsFixtures
  import PhoenixChat.ChatFixtures

  describe "huddle" do
    setup :register_and_log_in_user

    test "redirects anonymous users to login" do
      conn = Phoenix.ConnTest.build_conn()
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/huddle/general")
    end

    test "renders the huddle stage for members", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/huddle/general")

      for id <-
            ~w(rtc-root video-grid local-video controls-bar btn-mic btn-cam btn-share chat-panel messages chat-form participants) do
        assert has_element?(view, "##{id}")
      end

      assert has_element?(view, ~s{#rtc-root[data-display-name="#{user.username}"]})
      assert has_element?(view, ~s{#rtc-root[data-room-id="general"]})
    end

    test "bounces non-members to the app", %{conn: conn} do
      other = user_fixture()
      channel_fixture(other, %{name: "privatna-ekipa"})

      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/huddle/privatna-ekipa")
    end

    test "in-huddle chat renders messages", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/huddle/general")

      view |> form("#chat-form", %{text: "test u sobi"}) |> render_submit()
      assert render(view) =~ "test u sobi"
    end
  end
end
```

And append to `chat_live_test.exs` (inside `describe "channel view"`):

```elixir
    test "channel header links to the huddle", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")
      assert has_element?(view, ~s{#huddle-link[href="/huddle/general"]})
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/phoenix_chat_web/live/room_live_test.exs test/phoenix_chat_web/live/chat_live_test.exs`
Expected: FAIL — `/huddle/:slug` route missing, old RoomLive tests replaced.

- [ ] **Step 3: Router** — remove `live "/r/:room_id", RoomLive, :show` from the public scope; add inside the `live_session :require_authenticated_user` block:

```elixir
      live "/huddle/:slug", RoomLive, :show
```

- [ ] **Step 4: RoomLive mount** — in `lib/phoenix_chat_web/live/room_live.ex`, add `alias PhoenixChat.Chat` and replace the whole `mount/3` with:

```elixir
  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    user = socket.assigns.current_scope.user
    channel = Chat.get_channel_by_slug!(slug)

    if Chat.member?(user, channel) do
      topic = "room:#{slug}"

      if connected?(socket) do
        Phoenix.PubSub.subscribe(PhoenixChat.PubSub, topic)
      end

      entries =
        Presence.list(topic)
        |> Enum.map(fn {id, %{metas: [meta | _]}} -> build_entry(id, meta) end)

      participants_count = length(entries)

      socket =
        socket
        |> assign(
          room_id: slug,
          channel: channel,
          display_name: user.username,
          page_title: gettext("Huddle") <> " · " <> huddle_name(channel),
          participants_count: participants_count,
          participants_empty?: participants_count == 0,
          chat_form: to_form(%{"text" => ""}),
          chat_sending?: false
        )
        |> stream(:messages, [], reset: true)
        |> stream(:participants, entries, reset: true)

      Logger.info("huddle mounted", room_id: slug, display_name: user.username)

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("You are not a member of this channel"))
       |> push_navigate(to: ~p"/")}
    end
  end

  defp huddle_name(%{kind: :dm}), do: gettext("Direct message")
  defp huddle_name(channel), do: "#" <> channel.name
```

(All `handle_info`/`handle_event` clauses and `build_entry/2`/`sanitize_text/1` stay exactly as they are.)

- [ ] **Step 5: Rewrite the template** — replace `lib/phoenix_chat_web/live/room_live.html.heex` with:

```heex
<div class="hdl-stage">
  <header class="hdl-header">
    <a href="/" class="hdl-back">←</a>
    <span class="hdl-title">{@page_title}</span>
    <span class="hdl-user">{@display_name}</span>
    <span class="hdl-count">
      {ngettext("%{count} participant", "%{count} participants", @participants_count)}
    </span>
  </header>

  <div class="hdl-body">
    <div class="hdl-main">
      <div id="video-grid">
        <div
          id="rtc-root"
          phx-hook="RoomRTC"
          data-room-id={@room_id}
          data-display-name={@display_name}
        >
        </div>
        <video id="local-video" muted autoplay playsinline></video>
      </div>

      <div id="controls-bar" class="hdl-controls">
        <button id="btn-mic" type="button">{gettext("Mic")}</button>
        <button id="btn-cam" type="button">{gettext("Camera")}</button>
        <button id="btn-share" type="button">{gettext("Share screen")}</button>
        <video id="screen-video" class="hidden" muted autoplay playsinline></video>

        <form id="device-form">
          <select id="sel-mic" name="mic" aria-label={gettext("Microphone")}></select>
          <select id="sel-cam" name="cam" aria-label={gettext("Camera")}></select>
        </form>
      </div>
    </div>

    <aside class="hdl-side">
      <div id="participants" phx-update="stream">
        <div id="participants-empty" class="hidden only:block">
          {gettext("No participants yet")}
        </div>
        <div :for={{id, p} <- @streams.participants} id={id} class="participant-row">
          {p.display_name}
          {if(p.audio_muted, do: " 🔇")}
          {if(!p.video_enabled, do: " 📷✕")}
        </div>
      </div>

      <div id="chat-panel">
        <div id="messages" phx-update="stream">
          <div id="messages-empty" class="hidden only:block">{gettext("No messages yet")}</div>
          <div :for={{id, m} <- @streams.messages} id={id} class="chat-msg">
            <span class="chat-name">{m.display_name}</span>: <span class="chat-text">{m.text}</span>
          </div>
        </div>

        <.form for={@chat_form} id="chat-form" phx-submit="chat:send">
          <input
            type="text"
            name="text"
            value={@chat_form[:text].value}
            placeholder={gettext("Type a message...")}
            autocomplete="off"
          />
          <button id="send-chat" type="submit">{gettext("Send")}</button>
        </.form>
      </div>
    </aside>
  </div>
</div>

<Layouts.flash_group flash={@flash} />
```

Note: the old template's `RoomRTC` contract is preserved (`data-room-id`, `data-display-name`, all element ids). The device selects lose the `<.input>` wrapper — the hook only queries `#sel-mic` / `#sel-cam` by id, so a bare `<select>` works. The `<video id="screen-video">` keeps the `hidden` class the hook toggles.

- [ ] **Step 6: Huddle link in the channel header** — in `chat_live.html.heex`, the `<.channel_header ...>` call becomes:

```heex
      <.channel_header title={@conversation_title} topic={@active.topic}>
        <:actions>
          <a
            :if={!@gate?}
            id="huddle-link"
            href={~p"/huddle/#{@active.slug}"}
            target="_blank"
            rel="noopener"
            class="cds-btn-tertiary"
          >
            {gettext("Start huddle")}
          </a>
        </:actions>
      </.channel_header>
```

- [ ] **Step 7: Replace the PoC CSS** — in `assets/css/app.css`, delete everything from the `/* =========================================================
   PoC minimal, clean CSS` comment block down to the end of the old `@media (max-width: 640px) { ... }` responsive-tweaks rule, and put this in its place:

```css
/* === Huddle (Carbon dark stage) === */
.hdl-stage { display: flex; flex-direction: column; height: 100vh; background: #161616; color: #ffffff; }
.hdl-header { height: 48px; flex: none; display: flex; align-items: center; gap: 16px; padding: 0 16px; border-bottom: 1px solid #262626; }
.hdl-back { color: #ffffff; font-size: 16px; text-decoration: none; }
.hdl-title { font-size: 14px; font-weight: 600; }
.hdl-user { font-size: 12px; color: #c6c6c6; }
.hdl-count { margin-left: auto; font-size: 12px; color: #c6c6c6; }
.hdl-body { flex: 1; display: flex; min-height: 0; }
.hdl-main { flex: 1; display: flex; flex-direction: column; gap: 16px; min-width: 0; padding: 16px; }
#video-grid { flex: 1; display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 8px; align-content: start; overflow-y: auto; }
#video-grid video, #local-video { width: 100%; aspect-ratio: 16 / 9; height: auto; object-fit: cover; background: #000; border: 1px solid #262626; display: block; }
#local-video { border-color: #0f62fe; }
#screen-video.hidden { display: none; }
.hdl-controls { flex: none; display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.hdl-controls button { background: #262626; color: #ffffff; border: 1px solid #393939; padding: 11px 15px; font-size: 14px; cursor: pointer; }
.hdl-controls button:hover { background: #393939; }
.hdl-controls button[aria-pressed="true"] { background: #0f62fe; border-color: #0f62fe; }
#device-form { display: flex; gap: 8px; margin-left: auto; }
#device-form select { background: #262626; color: #ffffff; border: 1px solid #393939; padding: 8px; font-size: 12px; min-width: 8rem; }
.hdl-side { width: 320px; flex: none; display: flex; flex-direction: column; background: #ffffff; color: #161616; border-left: 1px solid #e0e0e0; }
#participants { flex: none; max-height: 30%; overflow-y: auto; padding: 8px 0; border-bottom: 1px solid #e0e0e0; }
.participant-row { display: flex; align-items: center; gap: 8px; padding: 6px 16px; font-size: 14px; }
#chat-panel { flex: 1; display: flex; flex-direction: column; min-height: 0; }
#messages { flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 4px; padding: 8px 16px; font-size: 14px; }
.chat-msg { overflow-wrap: anywhere; }
.chat-msg .chat-name { font-weight: 600; }
#chat-form { flex: none; display: flex; gap: 8px; padding: 8px 16px 16px; }
#chat-form input[type="text"] { flex: 1; min-width: 0; background: #f4f4f4; border: none; border-bottom: 1px solid #e0e0e0; padding: 11px 16px; font-size: 14px; letter-spacing: 0.16px; }
#chat-form input[type="text"]:focus { outline: none; border-bottom: 2px solid #0f62fe; padding-bottom: 10px; }
#chat-form button { background: #0f62fe; color: #ffffff; border: none; padding: 11px 16px; font-size: 14px; cursor: pointer; }
#messages > .only\:block, #participants > .only\:block { display: none; }
#messages > .only\:block:only-child, #participants > .only\:block:only-child { display: block; }
```

- [ ] **Step 8: Run tests**

Run: `mix test`
Expected: PASS, `0 failures`. Also `mix compile --warnings-as-errors` clean (the old `Ecto.UUID` lobby leftovers are gone with the mount rewrite).

- [ ] **Step 9: Manual smoke (two tabs)**

`mix phx.server` → log in in two browsers (register two users), both open `#general` → "Start huddle" → both land in `/huddle/general`, grant camera → verify two tiles + in-room chat. Stop server. (WebRTC itself is not covered by ExUnit — this is the verification for the untouched signaling path.)

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "Move video rooms to authenticated per-channel huddles" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 17: Gettext — Serbian default locale

**Files:**
- Modify: `config/config.exs`, `config/test.exs`, `lib/phoenix_chat_web/components/layouts/root.html.heex`, auth LiveViews under `lib/phoenix_chat_web/live/user_live/*.ex` (wrap raw strings)
- Create: `priv/gettext/sr/LC_MESSAGES/default.po`, `priv/gettext/sr/LC_MESSAGES/errors.po`

**Interfaces:**
- Consumes: every `gettext(...)` call written in T9–T16.
- Produces: dev/prod UI renders Serbian; tests keep English (`default_locale: "en"` in test env); `<html lang>` reflects the active locale.

- [ ] **Step 1: Config**

Append to `config/config.exs` (near the other endpoint config):

```elixir
config :phoenix_chat, PhoenixChatWeb.Gettext, default_locale: "sr", locales: ~w(en sr)
```

Append to `config/test.exs` (assertions in tests are written against English msgids):

```elixir
config :phoenix_chat, PhoenixChatWeb.Gettext, default_locale: "en"
```

In `root.html.heex`, change the html tag:

```heex
<html lang={Gettext.get_locale(PhoenixChatWeb.Gettext)} data-theme="light">
```

- [ ] **Step 2: Wrap the generated auth pages**

The phx.gen.auth LiveViews ship with raw English copy. In `lib/phoenix_chat_web/live/user_live/registration.ex`, `login.ex`, `settings.ex`, `confirmation.ex` (and the `UserAuth` flash messages in `lib/phoenix_chat_web/user_auth.ex`), wrap every user-facing string in `gettext(...)`. Find them with:

```bash
grep -rn '"[A-Z][a-z].*"' lib/phoenix_chat_web/live/user_live/ lib/phoenix_chat_web/user_auth.ex | grep -v gettext | grep -v "~p" | grep -v "@"
```

Mechanical rule: headings, labels, buttons, link texts, `put_flash` texts → `gettext("...")`. Route paths, css classes, ids stay untouched.

- [ ] **Step 3: Extract and create the sr locale**

```bash
mix gettext.extract --merge
mix gettext.merge priv/gettext --locale=sr
```

Expected: `priv/gettext/sr/LC_MESSAGES/{default.po,errors.po}` created with all msgids, empty msgstr.

- [ ] **Step 4: Translate `default.po` (sr)**

Set the plural-forms header in both sr .po files:

```
"Plural-Forms: nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);\n"
```

Fill every msgstr. Translations for the app's own strings:

| msgid | msgstr (sr) |
|---|---|
| Channels | Kanali |
| Direct messages | Direktne poruke |
| New direct message | Nova direktna poruka |
| No other users yet. | Još nema drugih korisnika. |
| Log out | Odjavi se |
| Settings | Podešavanja |
| Send | Pošalji |
| Message %{name} | Poruka za %{name} |
| No messages yet — start the conversation. | Još nema poruka — započni razgovor. |
| Load older messages | Učitaj starije poruke |
| You are not a member of this channel | Nisi član ovog kanala |
| You cannot message yourself | Ne možeš slati poruke samom sebi |
| Close | Zatvori |
| Add reaction | Dodaj reakciju |
| Create channel | Napravi kanal |
| Browse channels | Pregledaj kanale |
| Name | Naziv |
| e.g. marketing | npr. marketing |
| Topic (optional) | Tema (opciono) |
| Create | Napravi |
| Join | Pridruži se |
| Join channel | Pridruži se kanalu |
| No channels to join. | Nema kanala za pridruživanje. |
| You are not a member of %{name} yet. | Još nisi član kanala %{name}. |
| Start huddle | Pokreni huddle |
| Huddle | Huddle |
| Direct message | Direktna poruka |
| Mic | Mikrofon |
| Camera | Kamera |
| Share screen | Podeli ekran |
| Microphone | Mikrofon |
| No participants yet | Još nema učesnika |
| No messages yet | Još nema poruka |
| Type a message... | Ukucaj poruku... |
| We can't find the internet | Ne možemo da nađemo internet |
| Attempting to reconnect | Pokušavamo ponovo da se povežemo |
| Something went wrong! | Nešto je pošlo po zlu! |
| close | zatvori |
| Username | Korisničko ime |

Plural entry (participants):

```
msgid "%{count} participant"
msgid_plural "%{count} participants"
msgstr[0] "%{count} učesnik"
msgstr[1] "%{count} učesnika"
msgstr[2] "%{count} učesnika"
```

Auth-page strings (Log in → "Prijavi se", Register → "Registruj se", Email → "Imejl", Password → "Lozinka", "Keep me logged in" → "Ostavi me prijavljenog", etc.) — translate whatever msgids Step 2's wrapping produced, in the same register (informal ti-form, sentence case per DESIGN.md).

- [ ] **Step 5: Translate `errors.po` (sr)**

The changeset messages that appear in the UI (add msgids manually if extraction didn't pick them up — schema `message:` options are runtime strings):

```
msgid "can't be blank"
msgstr "obavezno polje"

msgid "has already been taken"
msgstr "već je zauzeto"

msgid "is invalid"
msgstr "nije ispravno"

msgid "only lowercase letters, numbers and dashes"
msgstr "samo mala slova, brojevi i crtice"

msgid "only letters, numbers and _ . - allowed"
msgstr "dozvoljena su samo slova, brojevi i _ . -"

msgid "should be at least %{count} character(s)"
msgid_plural "should be at least %{count} character(s)"
msgstr[0] "mora imati najmanje %{count} karakter"
msgstr[1] "mora imati najmanje %{count} karaktera"
msgstr[2] "mora imati najmanje %{count} karaktera"

msgid "should be at most %{count} character(s)"
msgid_plural "should be at most %{count} character(s)"
msgstr[0] "sme imati najviše %{count} karakter"
msgstr[1] "sme imati najviše %{count} karaktera"
msgstr[2] "sme imati najviše %{count} karaktera"
```

- [ ] **Step 6: Completeness check**

```bash
grep -n 'msgstr ""' priv/gettext/sr/LC_MESSAGES/*.po | grep -v "msgid \"\"" || echo "SR COMPLETE"
```

Expected: `SR COMPLETE` (the only empty msgstr allowed is the header entry — if the grep prints real entries, translate them and re-run).

- [ ] **Step 7: Verify**

Run: `mix test`
Expected: PASS (tests run under `en`).
Then `mix phx.server` → http://localhost:4000 → login page and app render in Serbian ("Kanali", "Pošalji", "Pokreni huddle"). Stop server.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Localize UI to Serbian via gettext with English fallback" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 18: Seeds, precommit gate, final smoke

**Files:**
- Modify: `priv/repo/seeds.exs`

**Interfaces:**
- Consumes: `Chat.ensure_general_channel!/0`, `join_general/1`, `send_message/3`, `get_or_create_dm!/2`; `Accounts.get_user_by_email/1`; `Bcrypt` (via bcrypt_elixir from T1).
- Produces: idempotent seeds — `#general` always; in dev: users `ana|marko|jovana@demo.local` (password `lozinka12345`, confirmed) + sample conversation.

- [ ] **Step 1: Write seeds** — replace `priv/repo/seeds.exs` with:

```elixir
# Idempotent seeds. Run with: mix run priv/repo/seeds.exs
alias PhoenixChat.{Accounts, Chat, Repo}
alias PhoenixChat.Accounts.User

general = Chat.ensure_general_channel!()

if Mix.env() == :dev do
  demo = [
    {"ana@demo.local", "ana"},
    {"marko@demo.local", "marko"},
    {"jovana@demo.local", "jovana"}
  ]

  users =
    for {email, username} <- demo do
      case Accounts.get_user_by_email(email) do
        nil ->
          user =
            Repo.insert!(%User{
              email: email,
              username: username,
              hashed_password: Bcrypt.hash_pwd_salt("lozinka12345"),
              confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

          {:ok, _} = Chat.join_general(user)
          user

        %User{} = user ->
          user
      end
    end

  [ana, marko, jovana] = users

  {existing, _cursor} = Chat.list_messages(general, limit: 1)

  if existing == [] do
    {:ok, _} = Chat.send_message(ana, general, %{body: "Dobrodošli u PhoenixChat! 🎉"})
    {:ok, _} = Chat.send_message(marko, general, %{body: "Radi ovo odlično."})
    {:ok, _} = Chat.send_message(jovana, general, %{body: "Pozdrav ekipa!"})

    dm = Chat.get_or_create_dm!(ana, marko)
    {:ok, _} = Chat.send_message(ana, dm, %{body: "Marko, vidimo se na huddle-u?"})
  end
end
```

(If the generated users schema stores `confirmed_at` as `:utc_datetime_usec`, drop the `truncate` — match the schema. Direct struct insert deliberately bypasses registration so seeds can set a known password.)

- [ ] **Step 2: Fresh-database proof**

```bash
mix ecto.reset
```

Expected: drops, creates, migrates, seeds — exits 0. Run it TWICE (second run proves idempotency: `mix run priv/repo/seeds.exs`).

- [ ] **Step 3: The gate**

```bash
mix precommit
```

Expected: compiles with zero warnings, no unused deps, formatted, all tests pass. Fix anything it flags before proceeding.

- [ ] **Step 4: Full manual smoke**

`mix phx.server`, then walk through (two browsers, ana + marko, password `lozinka12345`):
1. Login both → both land in `#general` with seeded messages, Serbian UI
2. ana sends → appears instantly for marko; marko in `#general`, ana creates `#novi` and posts → marko sees unread badge on browse... (marko joins via ⌕ browse modal → badge/live flow)
3. ana → DM marko (+ dugme) → message → marko's sidebar DM row bumps; online dots green for both
4. Reaction: marko hovers ana's message → + → 👍; ana sees chip count live
5. "Pokreni huddle" from `#general` in both browsers → two video tiles, in-huddle chat works
6. Log out → `/` redirects to login

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add idempotent seeds with dev demo users" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Spec coverage map

| Spec section | Tasks |
|---|---|
| §3 Data model (users/channels/memberships/messages/reactions) | T1–T3, T5, T6, T8 |
| §4 Contexts (Accounts + Chat API) | T2–T8 |
| §5 LiveView architecture (routes, ChatLive, PubSub, hooks) | T10–T15 |
| §6 UI Carbon (tokens, fonts, layout, components, gettext-from-start) | T9–T16 |
| §7 Auth & huddle | T1, T2, T4, T16 |
| §8 Error handling (validation, constraints, gates, 404s) | T2, T3, T6, T8, T15 |
| §9 Testing | every task (TDD) |
| §10 Seeds & dev experience | T0, T18 |
| Known gaps (spec §1 non-goals) | intentionally unplanned |
