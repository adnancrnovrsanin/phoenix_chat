# Complete Slack Clone — Phase 0 (Foundation) + Phase 1 (Messaging Depth) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the in-progress "Glass" theme on a green build, add the multi-workspace schema seam, then deliver Slack-style messaging depth — threads, edit/delete, markdown, a full emoji picker, typing indicators, and an unread divider.

**Architecture:** Extend in place. Single `ChatLive` shell + `Chat` context (authorization at the boundary), DMs modeled as `channels` rows with `kind: :dm`, LiveView streams + one PubSub topic per channel (`chat:channel:#{id}`). Threads use a self-referential `messages.parent_message_id` with denormalized `reply_count`/`last_reply_at`; edits/deletes are soft (`edited_at`/`deleted_at`); markdown renders server-side via MDEx; the emoji picker is a dependency-free LiveComponent over a vendored dataset.

**Tech Stack:** Phoenix 1.8 · LiveView 1.2 · Ecto/Postgres 17 (port 5433) · Tailwind v4 (Glass tokens, Inter, no npm) · MDEx (markdown) · gettext (sr default) · Bandit.

**Spec:** `docs/superpowers/specs/2026-07-14-slack-clone-messaging-depth-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- Elixir `~> 1.18`, Phoenix `~> 1.8`, LiveView `~> 1.2`, Postgres 17 via container `phoenix-chat-db` on **port 5433** (user/pass `postgres/postgres`).
- All Chat-context timestamps: `utc_datetime_usec`. bigserial PKs. `Ecto.Enum` for kinds.
- **Authorization is enforced at the `Chat` context boundary** — functions return `{:error, :not_a_member}` / `{:error, :unauthorized}`; the LiveView never bypasses it.
- Messaging soft-deletes only (`deleted_at` tombstone) — no hard deletes. Reactions accept **any** emoji (validated: single grapheme, ≤16 bytes). Channel unread counts **root messages only** (`parent_message_id IS NULL`).
- Markdown is rendered server-side (MDEx) and **sanitized** — no raw HTML/script from message bodies. Slack-lite feature set (no images/tables/raw HTML).
- Assets are **npm-free** (pure esbuild); the emoji picker adds no JS dependency.
- All user-facing strings use `gettext("English text")` from the moment they are written; `sr` translations added in the final task.
- Every task ends green: `mix test` passes. Final gate: `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, test).
- Commit style: short imperative subject, no conventional-commit prefix. Every commit:
  `git commit -m "<subject>" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

## Task order

**Phase 0:** T1 Land Glass theme → T2 Workspace seam.
**Phase 1:** T3 Schema (thread/edit/delete cols + reaction changeset) → T4 Threads context → T5 Edit/delete/reactions/unread context → T6 Markdown → T7 Emoji dataset+component → T8 Message actions + edit/delete UI → T9 Emoji picker wired (reactions+composer) → T10 Thread panel → T11 Typing → T12 Unread divider → T13 i18n + final precommit.

---

### Task 1: Land the Glass theme (green baseline)

This is an **ops / cleanup** task, not TDD. The working tree already contains a coherent, mostly-complete "Glass" re-theme (Glass tokens + vendored Inter `@font-face` in `assets/css/app.css`; restyled `core_components.ex`, `layouts.ex`, `root.html.heex`, `chat_live` templates, `room_live.html.heex`, all four `user_live` auth pages, plus a rewritten `DESIGN.md`). Task 1 **finishes and commits** it as one clean, green baseline: track the Inter fonts, delete the dead IBM Plex / daisyUI residue, fix the stale `core_components` moduledoc, and gate on `mix precommit`. No data-model change — purely presentation.

**Files:**
- Delete: `priv/static/fonts/ibm-plex-sans-latin-300.woff2`
- Delete: `priv/static/fonts/ibm-plex-sans-latin-400.woff2`
- Delete: `priv/static/fonts/ibm-plex-sans-latin-600.woff2`
- Delete: `priv/static/fonts/ibm-plex-sans-latin-ext-300.woff2`
- Delete: `priv/static/fonts/ibm-plex-sans-latin-ext-400.woff2`
- Delete: `priv/static/fonts/ibm-plex-sans-latin-ext-600.woff2`
- Delete: `assets/vendor/daisyui.js`
- Delete: `assets/vendor/daisyui-theme.js`
- Track (git add, currently untracked): `priv/static/fonts/inter-latin-400.woff2`, `priv/static/fonts/inter-latin-500.woff2`, `priv/static/fonts/inter-latin-600.woff2`, `priv/static/fonts/inter-latin-ext-400.woff2`, `priv/static/fonts/inter-latin-ext-500.woff2`, `priv/static/fonts/inter-latin-ext-600.woff2`
- Modify: `lib/phoenix_chat_web/components/core_components.ex` (moduledoc of `PhoenixChatWeb.CoreComponents` — remove the false daisyUI claim, describe the Glass semantic-token system)
- Modify (commit the in-progress re-theme already in the working tree): `DESIGN.md`, `assets/css/app.css`, `assets/js/app.js`, `lib/phoenix_chat_web/components/layouts.ex`, `lib/phoenix_chat_web/components/layouts/root.html.heex`, `lib/phoenix_chat_web/live/chat_live.ex`, `lib/phoenix_chat_web/live/chat_live.html.heex`, `lib/phoenix_chat_web/live/chat_live/components.ex`, `lib/phoenix_chat_web/live/room_live.html.heex`, `lib/phoenix_chat_web/live/user_live/confirmation.ex`, `lib/phoenix_chat_web/live/user_live/login.ex`, `lib/phoenix_chat_web/live/user_live/registration.ex`, `lib/phoenix_chat_web/live/user_live/settings.ex`
- Test: none created — this is a presentation/ops change. The gate is the existing suite via `mix test` (equivalently `mix precommit`).

**Interfaces:**
- Consumes: repo `mix precommit` alias (`compile --warning-as-errors`, `deps.unlock --unused`, `format`, `test`); Glass tokens + Inter `@font-face` already present in `assets/css/app.css`.
- Produces: a green baseline commit on `master`; 6 tracked Inter `.woff2` files; Glass semantic-token utilities (`bg-surface`, `text-muted`, `border-separator`, `bg-accent`, `text-danger`, `field-*`) available to all later LiveView markup; `DESIGN.md` (Glass) as source of truth; zero `daisyui` references in loaded code.

---

- [ ] **Step 1: Delete the dead IBM Plex Sans woff2 set** (orphaned — referenced by no `@font-face`; confirmed via `grep -rn "ibm-plex" assets lib priv config` → no hits). These 6 files are git-tracked, so remove them with `git rm`:

```bash
cd /Users/adnan/Projects/phoenix_chat
git rm priv/static/fonts/ibm-plex-sans-latin-300.woff2 \
       priv/static/fonts/ibm-plex-sans-latin-400.woff2 \
       priv/static/fonts/ibm-plex-sans-latin-600.woff2 \
       priv/static/fonts/ibm-plex-sans-latin-ext-300.woff2 \
       priv/static/fonts/ibm-plex-sans-latin-ext-400.woff2 \
       priv/static/fonts/ibm-plex-sans-latin-ext-600.woff2
```

  Expected output (6 lines):
```
rm 'priv/static/fonts/ibm-plex-sans-latin-300.woff2'
rm 'priv/static/fonts/ibm-plex-sans-latin-400.woff2'
rm 'priv/static/fonts/ibm-plex-sans-latin-600.woff2'
rm 'priv/static/fonts/ibm-plex-sans-latin-ext-300.woff2'
rm 'priv/static/fonts/ibm-plex-sans-latin-ext-400.woff2'
rm 'priv/static/fonts/ibm-plex-sans-latin-ext-600.woff2'
```

- [ ] **Step 2: Delete the dead daisyUI vendor bundles** (vendored but never loaded — `assets/css/app.css` only `@plugin`s `../vendor/heroicons`; `assets/js/app.js` imports only `../vendor/topbar`; both daisyui files are git-tracked):

```bash
cd /Users/adnan/Projects/phoenix_chat
git rm assets/vendor/daisyui.js assets/vendor/daisyui-theme.js
```

  Expected output:
```
rm 'assets/vendor/daisyui.js'
rm 'assets/vendor/daisyui-theme.js'
```

- [ ] **Step 3: Track the 6 untracked Inter woff2 files** (without this the theme breaks in a fresh checkout / prod build — `app.css` `@font-face` `src` points at `/fonts/inter-*.woff2`):

```bash
cd /Users/adnan/Projects/phoenix_chat
git add priv/static/fonts/inter-latin-400.woff2 \
        priv/static/fonts/inter-latin-500.woff2 \
        priv/static/fonts/inter-latin-600.woff2 \
        priv/static/fonts/inter-latin-ext-400.woff2 \
        priv/static/fonts/inter-latin-ext-500.woff2 \
        priv/static/fonts/inter-latin-ext-600.woff2
git status --short priv/static/fonts/
```

  Expected output (the 6 Inter files now staged as additions, the 6 Plex files staged as deletions):
```
A  priv/static/fonts/inter-latin-400.woff2
A  priv/static/fonts/inter-latin-500.woff2
A  priv/static/fonts/inter-latin-600.woff2
A  priv/static/fonts/inter-latin-ext-400.woff2
A  priv/static/fonts/inter-latin-ext-500.woff2
A  priv/static/fonts/inter-latin-ext-600.woff2
D  priv/static/fonts/ibm-plex-sans-latin-300.woff2
D  priv/static/fonts/ibm-plex-sans-latin-400.woff2
D  priv/static/fonts/ibm-plex-sans-latin-600.woff2
D  priv/static/fonts/ibm-plex-sans-latin-ext-300.woff2
D  priv/static/fonts/ibm-plex-sans-latin-ext-400.woff2
D  priv/static/fonts/ibm-plex-sans-latin-ext-600.woff2
```

- [ ] **Step 4: Fix the stale moduledoc** in `lib/phoenix_chat_web/components/core_components.ex`. The `@moduledoc` of `PhoenixChatWeb.CoreComponents` still claims daisyUI is "the foundation for styling" and links the daisyUI docs — both false (daisyUI was removed in Steps 1–2). Replace the daisyUI paragraph + bullet with a description of the Glass semantic-token system, keeping the Tailwind, Heroicons, and Phoenix.Component bullets intact.

  Apply this exact edit (replace the first block with the second):

  Old (verbatim, lines beginning at "The foundation for styling…"):
```elixir
  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
```

  New (verbatim replacement):
```elixir
  The foundation for styling is Tailwind CSS v4, a utility-first CSS
  framework, driven by the "Glass" design system. Rather than branching on
  light/dark, components use semantic utilities (`bg-surface`, `text-muted`,
  `border-separator`, `bg-accent`, `text-danger`, `field-*`…) whose values
  are defined once in `assets/css/app.css` and flip automatically via the
  `[data-theme]` attribute set by the theme toggle. See `DESIGN.md` for the
  full token reference. Useful references:

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
```

  After this edit the moduledoc reads: intro paragraph (unchanged) → the new Glass paragraph → Tailwind CSS bullet → Heroicons bullet → Phoenix.Component bullet (both trailing bullets unchanged).

- [ ] **Step 5: Verify no daisyUI references remain in loaded code.** After Steps 1–2 and 4, the only former `daisyui` hits (the two moduledoc lines and the two deleted vendor files) are gone:

```bash
cd /Users/adnan/Projects/phoenix_chat
grep -rin "daisyui" lib assets config mix.exs && echo "FOUND — fix before continuing" || echo "clean: no daisyui in loaded code"
```

  Expected output:
```
clean: no daisyui in loaded code
```

- [ ] **Step 6: Compile with warnings as errors** (matches the `precommit` alias's `compile --warning-as-errors`; the working tree already compiled clean before this task):

```bash
cd /Users/adnan/Projects/phoenix_chat
mix compile --warning-as-errors
```

  Expected: exit status `0` with no warnings (an already-compiled clean tree prints nothing; a fresh build prints `Compiling N files (.ex)` and then exits 0 — no `warning:` lines).

- [ ] **Step 7: Check formatting** (matches the `precommit` alias's `format`; verified passing on the current tree):

```bash
cd /Users/adnan/Projects/phoenix_chat
mix format --check-formatted
```

  Expected: exit status `0`, no output. (If it lists files, run `mix format` and re-run until clean — the moduledoc edit in Step 4 is inside a docstring and should not affect formatting.)

- [ ] **Step 8: Run the full test suite** (the green gate — equivalent to `mix precommit`'s `test`):

```bash
cd /Users/adnan/Projects/phoenix_chat
mix test
```

  Expected: all tests pass, e.g. a final line like `Finished in 0.X seconds` / `NN tests, 0 failures`. Zero failures is required to proceed. (This task is presentation-only and adds no tests; it must not regress any existing test.)

- [ ] **Step 9: Manual smoke-check both light & dark render** (visual verification only — the Glass tokens must resolve on every surface in both color schemes; no automated assertion):

```bash
cd /Users/adnan/Projects/phoenix_chat
mix phx.server
```

  Then open `http://localhost:4000`, sign in (dev seed user), and eyeball each surface in **both** themes using the theme toggle (which stamps `[data-theme="light"|"dark"]` on `:root`):
  - Chat shell: sidebar, channel header, message list, composer, any modals
  - Auth pages: `/users/log-in`, `/users/register`, `/users/settings`, confirmation
  - Huddle room (`room_live`), flash notices, and empty states ("No messages yet")

  Observation note to confirm before continuing: text stays legible (`text-foreground` / `text-muted`), surfaces use `bg-surface` / `bg-background*`, separators/borders render (`border-separator` / `border-border`), and **nothing** is unstyled or invisible in either scheme. Stop the server with `Ctrl-C` twice (`^C^C`) when done.

- [ ] **Step 10: Stage the whole re-theme and commit as one clean baseline.** Stage every remaining working-tree change (the in-progress Glass restyle across `DESIGN.md`, `app.css`, `app.js`, `layouts.ex`, `root.html.heex`, the `chat_live` / `room_live` templates, and all four `user_live` auth pages) together with the Step 1–4 changes, then commit:

```bash
cd /Users/adnan/Projects/phoenix_chat
git add -A
git status --short
```

  Expected `git status --short` (staged): 6 `A` Inter fonts, 6 `D` Plex fonts, 2 `D` daisyui vendor files, and `M` for `DESIGN.md`, `assets/css/app.css`, `assets/js/app.js`, `lib/phoenix_chat_web/components/core_components.ex`, `lib/phoenix_chat_web/components/layouts.ex`, `lib/phoenix_chat_web/components/layouts/root.html.heex`, `lib/phoenix_chat_web/live/chat_live.ex`, `lib/phoenix_chat_web/live/chat_live.html.heex`, `lib/phoenix_chat_web/live/chat_live/components.ex`, `lib/phoenix_chat_web/live/room_live.html.heex`, `lib/phoenix_chat_web/live/user_live/confirmation.ex`, `lib/phoenix_chat_web/live/user_live/login.ex`, `lib/phoenix_chat_web/live/user_live/registration.ex`, `lib/phoenix_chat_web/live/user_live/settings.ex` — and nothing left in the unstaged/untracked sections.

  Then commit (repo convention: short imperative subject, no conventional-commit prefix, Co-Authored-By trailer):

```bash
git commit -m "Land the Glass theme and retire dead daisyUI/Plex assets" \
  -m "Track vendored Inter woff2 fonts; delete orphaned IBM Plex Sans set and unused daisyui.js/daisyui-theme.js vendor bundles; rewrite CoreComponents moduledoc to describe the Glass semantic-token system; commit DESIGN.md (Glass) as the design source of truth." \
  -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

  Expected: one commit created summarizing the file changes (Inter fonts added, Plex + daisyui files deleted, the listed files modified). `git status` afterward is clean (`nothing to commit, working tree clean`).

- [ ] **Step 11: Confirm the green baseline** so later tasks branch from a clean, passing `master`:

```bash
cd /Users/adnan/Projects/phoenix_chat
mix precommit
```

  Expected: runs `compile --warning-as-errors`, `deps.unlock --unused`, `format`, `test` in sequence and exits `0` with `NN tests, 0 failures`. This is the gate for Task 1 — do not proceed to Task 2 until it passes.

---

### Task 2: Workspace schema seam

Introduce the multi-tenancy seam: a `workspaces` table, a not-null `channels.workspace_id` (with a backfill of every existing channel **and** DM to the seeded default workspace), a race-safe `Chat.default_workspace!/0`, and workspace-scoped channel listings. No user-facing workspace UI (that is Phase 3). All Chat-context authorization and behavior stay at the context boundary.

**Files:**
- Create: `priv/repo/migrations/20260714090000_create_workspaces_and_backfill_channels.exs`
- Create: `lib/phoenix_chat/chat/workspace.ex`
- Modify: `lib/phoenix_chat/chat/channel.ex` (add `belongs_to :workspace`; extend `create_changeset/2`)
- Modify: `lib/phoenix_chat/chat.ex` (alias `Workspace`; add `default_workspace!/0`; wire `ensure_general_channel!/0`, `create_channel/2`, `get_or_create_dm!/2`, `memberships_with_unread/2`, `list_browsable_channels/1`)
- Modify: `priv/repo/seeds.exs` (ensure default workspace exists)
- Test: `test/phoenix_chat/chat_test.exs` (add `default_workspace!/0` + `workspace scoping` describe blocks)

**Interfaces:**
- Consumes: existing `Chat.create_channel/2`, `Chat.ensure_general_channel!/0`, `Chat.get_or_create_dm!/2`, `Chat.list_joined_channels/1`, `Chat.list_browsable_channels/1`, `Channel.create_changeset/2`; `PhoenixChat.Repo`, `Ecto.Migration`.
- Produces:
  - `PhoenixChat.Chat.Workspace` schema — table `"workspaces"`, fields `name:string`, `slug:string`, `timestamps(type: :utc_datetime_usec)`, `has_many :channels`.
  - `PhoenixChat.Chat.Workspace.changeset/2` — casts `[:name, :slug]`, `validate_required([:name, :slug])`, `unique_constraint(:slug)`.
  - `PhoenixChat.Chat.default_workspace!/0 :: %Workspace{}` — idempotent, slug `"tenderr"`, name `"Tenderr"`, race-safe.
  - `PhoenixChat.Chat.Channel` gains `belongs_to :workspace, PhoenixChat.Chat.Workspace`; `channels.workspace_id` is not-null with `index(:channels, [:workspace_id])`.
  - `Channel.create_changeset/2` adds `validate_required([:workspace_id])` + `foreign_key_constraint(:workspace_id)`.

---

- [ ] **Step 1: Write the failing test.** Add a `Workspace` alias and two describe blocks to `test/phoenix_chat/chat_test.exs`. First, insert the alias directly under the existing `alias PhoenixChat.Chat.Channel` line so it reads:

```elixir
  alias PhoenixChat.Chat
  alias PhoenixChat.Chat.Channel
  alias PhoenixChat.Chat.Workspace
```

Then insert the following two describe blocks immediately **before** the final `end` of the module (right after the closing `end` of the `describe "reactions"` block):

```elixir
  describe "default_workspace!/0" do
    test "is idempotent and returns the tenderr workspace" do
      ws1 = Chat.default_workspace!()
      ws2 = Chat.default_workspace!()

      assert %Workspace{} = ws1
      assert ws1.id == ws2.id
      assert ws1.slug == "tenderr"
      assert ws1.name == "Tenderr"
    end
  end

  describe "workspace scoping" do
    test "create_channel/2 assigns the default workspace" do
      user = user_fixture()
      ch = channel_fixture(user)
      assert ch.workspace_id == Chat.default_workspace!().id
    end

    test "ensure_general_channel!/0 belongs to the default workspace" do
      ch = Chat.ensure_general_channel!()
      assert ch.workspace_id == Chat.default_workspace!().id
    end

    test "get_or_create_dm!/2 assigns the default workspace" do
      a = user_fixture()
      b = user_fixture()
      dm = Chat.get_or_create_dm!(a, b)
      assert dm.workspace_id == Chat.default_workspace!().id
    end

    test "list_joined_channels/1 excludes channels from other workspaces" do
      me = user_fixture()
      mine = channel_fixture(me, %{name: unique_channel_name()})

      n = System.unique_integer([:positive])
      other_ws = Repo.insert!(%Workspace{name: "Other #{n}", slug: "other-#{n}"})

      foreign =
        Repo.insert!(%Channel{
          kind: :channel,
          name: "foreign-#{n}",
          slug: "foreign-#{n}",
          workspace_id: other_ws.id
        })

      {:ok, _} = Chat.join_channel(me, foreign)

      ids = for %{channel: c} <- Chat.list_joined_channels(me), do: c.id
      assert mine.id in ids
      refute foreign.id in ids
    end

    test "list_browsable_channels/1 excludes channels from other workspaces" do
      me = user_fixture()
      mine_unjoined = channel_fixture(user_fixture(), %{name: unique_channel_name()})

      n = System.unique_integer([:positive])
      other_ws = Repo.insert!(%Workspace{name: "Other #{n}", slug: "other-#{n}"})

      foreign =
        Repo.insert!(%Channel{
          kind: :channel,
          name: "foreign-#{n}",
          slug: "foreign-#{n}",
          workspace_id: other_ws.id
        })

      ids = for c <- Chat.list_browsable_channels(me), do: c.id
      assert mine_unjoined.id in ids
      refute foreign.id in ids
    end
  end
```

(`Repo` and `from` are already available via `PhoenixChat.DataCase`; the existing suite uses both.)

- [ ] **Step 2: Run to verify it fails.**

```
mix test test/phoenix_chat/chat_test.exs
```

Expected: the test module fails to **compile** because the `%Workspace{}` struct literal and `Chat.default_workspace!/0` do not exist yet, e.g.:

```
== Compilation error in file test/phoenix_chat/chat_test.exs ==
** (CompileError) test/phoenix_chat/chat_test.exs: PhoenixChat.Chat.Workspace.__struct__/1 is undefined (module PhoenixChat.Chat.Workspace is not available)
```

- [ ] **Step 3: Create the `Workspace` schema.** Create `lib/phoenix_chat/chat/workspace.ex` with the complete module (mirrors the style of `channel.ex`):

```elixir
defmodule PhoenixChat.Chat.Workspace do
  use Ecto.Schema
  import Ecto.Changeset

  schema "workspaces" do
    field :name, :string
    field :slug, :string

    has_many :channels, PhoenixChat.Chat.Channel

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for creating/updating a workspace."
  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
  end
end
```

- [ ] **Step 4: Create the migration.** Create `priv/repo/migrations/20260714090000_create_workspaces_and_backfill_channels.exs`. It creates `workspaces`, adds `channels.workspace_id` nullable, seeds the default workspace, backfills every existing channel/DM to it, then sets the column not-null and indexes it. Uses explicit `up`/`down` because the backfill is a data migration:

```elixir
defmodule PhoenixChat.Repo.Migrations.CreateWorkspacesAndBackfillChannels do
  use Ecto.Migration

  def up do
    create table(:workspaces) do
      add :name, :string, null: false
      add :slug, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspaces, [:slug])

    alter table(:channels) do
      add :workspace_id, references(:workspaces, on_delete: :delete_all)
    end

    flush()

    now = NaiveDateTime.utc_now()

    %Postgrex.Result{rows: [[workspace_id]]} =
      repo().query!(
        "INSERT INTO workspaces (name, slug, inserted_at, updated_at) VALUES ($1, $2, $3, $3) RETURNING id",
        ["Tenderr", "tenderr", now]
      )

    repo().query!(
      "UPDATE channels SET workspace_id = $1 WHERE workspace_id IS NULL",
      [workspace_id]
    )

    execute("ALTER TABLE channels ALTER COLUMN workspace_id SET NOT NULL")

    create index(:channels, [:workspace_id])
  end

  def down do
    alter table(:channels) do
      remove :workspace_id
    end

    drop table(:workspaces)
  end
end
```

`NaiveDateTime.utc_now/0` yields microsecond precision and encodes cleanly into the `utc_datetime_usec` (`timestamp` without time zone) columns via raw Postgrex.

- [ ] **Step 5: Add the association + validation to `Channel`.** Replace the full contents of `lib/phoenix_chat/chat/channel.ex` with (adds `belongs_to :workspace`, and requires/constrains `workspace_id` in `create_changeset/2`; everything else unchanged):

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

    belongs_to :workspace, PhoenixChat.Chat.Workspace
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
    |> validate_required([:workspace_id])
    |> unique_constraint(:name, name: :channels_channel_name_index)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:workspace_id)
  end

  defp put_slug_from_name(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, name)
    end
  end
end
```

`workspace_id` is set on the `%Channel{}` struct by the caller (`Chat.create_channel/2`, Step 6), so `validate_required/2` reads it from the changeset data.

- [ ] **Step 6: Wire the `Chat` context.** Apply the following edits to `lib/phoenix_chat/chat.ex`.

(6a) Extend the alias to include `Workspace`:

```elixir
  alias PhoenixChat.Chat.{Channel, ChannelMembership, Message, MessageReaction, Workspace}
```

(6b) Add the default-workspace name attribute directly under the existing `@reaction_palette` line:

```elixir
  @reaction_palette ~w(👍 ❤️ 😂 🎉 👀 ✅ 🔥 🙏)

  @default_workspace_name "Tenderr"
```

(6c) Add a `## Workspaces` section with `default_workspace!/0` immediately above the existing `## Channels` comment:

```elixir
  ## Workspaces

  @doc """
  Idempotent get-or-create of the single default workspace (slug "tenderr").
  Race-safe like `ensure_general_channel!/0`.
  """
  def default_workspace! do
    case Repo.get_by(Workspace, slug: "tenderr") do
      %Workspace{} = workspace ->
        workspace

      nil ->
        case Repo.insert(%Workspace{name: @default_workspace_name, slug: "tenderr"},
               on_conflict: :nothing,
               conflict_target: :slug
             ) do
          {:ok, %Workspace{id: nil}} ->
            # Lost the race — the row was inserted by a concurrent caller; re-fetch.
            Repo.get_by!(Workspace, slug: "tenderr")

          {:ok, %Workspace{} = workspace} ->
            workspace
        end
    end
  end

```

(6d) Replace `create_channel/2` so the new `%Channel{}` struct carries `workspace_id` (rest unchanged):

```elixir
  def create_channel(%User{} = creator, attrs) do
    workspace = default_workspace!()

    result =
      %Channel{kind: :channel, workspace_id: workspace.id}
      |> Channel.create_changeset(attrs)
      |> Repo.insert()

    # Remap slug constraint errors to name field for consistency
    result =
      case result do
        {:error, %{errors: [{:slug, error} | rest]} = changeset} ->
          {:error, %{changeset | errors: [{:name, error} | rest]}}

        other ->
          other
      end

    with {:ok, channel} <- result do
      {:ok, _membership} = join_channel(creator, channel)
      {:ok, channel}
    end
  end
```

(6e) Replace `list_browsable_channels/1` to scope by the default workspace:

```elixir
  def list_browsable_channels(%User{} = user) do
    workspace = default_workspace!()

    joined_ids =
      from m in ChannelMembership, where: m.user_id == ^user.id, select: m.channel_id

    Repo.all(
      from c in Channel,
        where:
          c.kind == :channel and c.workspace_id == ^workspace.id and
            c.id not in subquery(joined_ids),
        order_by: [asc: c.name]
    )
  end
```

(6f) Replace `ensure_general_channel!/0` so the created `#general` carries `workspace_id`:

```elixir
  def ensure_general_channel! do
    case Repo.get_by(Channel, slug: "general") do
      %Channel{} = channel ->
        channel

      nil ->
        workspace = default_workspace!()

        case Repo.insert(
               %Channel{
                 kind: :channel,
                 name: "general",
                 slug: "general",
                 workspace_id: workspace.id
               },
               on_conflict: :nothing,
               conflict_target: :slug
             ) do
          {:ok, %Channel{id: nil}} ->
            # Lost the race — the row was inserted by a concurrent caller; re-fetch.
            Repo.get_by!(Channel, slug: "general")

          {:ok, %Channel{} = channel} ->
            channel
        end
    end
  end
```

(6g) Replace `memberships_with_unread/2` to scope by the default workspace (feeds both `list_joined_channels/1` and `list_dm_channels/1`):

```elixir
  defp memberships_with_unread(user, kind) do
    workspace = default_workspace!()

    Repo.all(
      from m in ChannelMembership,
        join: c in Channel,
        on: c.id == m.channel_id,
        where:
          m.user_id == ^user.id and c.kind == ^kind and c.workspace_id == ^workspace.id,
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

(6h) Replace `get_or_create_dm!/2` so newly created DMs carry `workspace_id` (required now that the column is not-null):

```elixir
  def get_or_create_dm!(%User{id: a_id} = a, %User{id: b_id} = b) when a_id != b_id do
    key = dm_key(a_id, b_id)

    case Repo.get_by(Channel, dm_key: key) do
      %Channel{} = channel ->
        channel

      nil ->
        workspace = default_workspace!()

        {:ok, channel} =
          Repo.transaction(fn ->
            channel =
              case Repo.insert(%Channel{
                     kind: :dm,
                     name: key,
                     slug: "dm-" <> key,
                     dm_key: key,
                     workspace_id: workspace.id
                   }) do
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
```

- [ ] **Step 7: Update the seeds.** In `priv/repo/seeds.exs`, make the default workspace explicit by replacing the line `general = Chat.ensure_general_channel!()` with:

```elixir
_workspace = Chat.default_workspace!()
general = Chat.ensure_general_channel!()
```

- [ ] **Step 8: Apply the migration to the dev DB.** (The `test` alias auto-runs `ecto.migrate --quiet`, so the test DB is migrated by Step 9; this migrates dev.)

```
mix ecto.migrate
```

Expected output includes:

```
* running 20260714090000 CreateWorkspacesAndBackfillChannels.up/0
== Migrated 20260714090000 in ...
```

- [ ] **Step 9: Run the full suite.** The `test` alias runs `ecto.create --quiet` then `ecto.migrate --quiet` (applying the new migration, committing the `"tenderr"` workspace before the sandbox begins) then the tests:

```
mix test
```

Expected: all tests pass, including the new `default_workspace!/0` and `workspace scoping` blocks and the unchanged DM/channel/listing/unread suites:

```
Finished in ...
XXX tests, 0 failures
```

- [ ] **Step 10: Commit.**

```
git add priv/repo/migrations/20260714090000_create_workspaces_and_backfill_channels.exs \
        lib/phoenix_chat/chat/workspace.ex \
        lib/phoenix_chat/chat/channel.ex \
        lib/phoenix_chat/chat.ex \
        priv/repo/seeds.exs \
        test/phoenix_chat/chat_test.exs
git commit -m "Add workspace schema seam" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Message thread/edit/delete columns + reaction changeset

**Files:**
- Create: `priv/repo/migrations/20260714120300_add_thread_edit_delete_to_messages.exs`
- Modify: `lib/phoenix_chat/chat/message.ex` (module `PhoenixChat.Chat.Message` — schema `"messages"`, `changeset/2`, new `edit_changeset/2`)
- Modify: `lib/phoenix_chat/chat/message_reaction.ex` (module `PhoenixChat.Chat.MessageReaction` — schema `"message_reactions"`, new `changeset/2`)
- Test: `test/phoenix_chat/chat/message_test.exs`
- Test: `test/phoenix_chat/chat/message_reaction_test.exs`

**Interfaces:**
- Consumes: existing `messages` table (`channel_id`, `user_id`, `body`, `timestamps :utc_datetime_usec`) and existing `message_reactions` table (`message_id`, `user_id`, `emoji`); existing schemas `PhoenixChat.Chat.Message` (`changeset/2` casts `[:body]`, trims, len 1..4000) and `PhoenixChat.Chat.MessageReaction` (no changeset yet). Assumes Task 2's `workspaces`/`channels.workspace_id` migration already exists — this migration's timestamp `20260714120300` must sort **after** Task 2's migration so `mix ecto.migrate` applies them in order.
- Produces:
  - `PhoenixChat.Chat.Message` gains fields `reply_count :integer (default 0)`, `last_reply_at :utc_datetime_usec`, `edited_at :utc_datetime_usec`, `deleted_at :utc_datetime_usec`, `also_sent_to_channel :boolean (default false)`; `belongs_to :parent, PhoenixChat.Chat.Message, foreign_key: :parent_message_id`; `has_many :replies, PhoenixChat.Chat.Message, foreign_key: :parent_message_id`.
  - `Message.changeset/2 :: %Ecto.Changeset{}` — casts `[:body, :parent_message_id, :also_sent_to_channel]`, trims + validates body (1..4000).
  - `Message.edit_changeset/2 :: %Ecto.Changeset{}` — casts `[:body]`, trims + validates body, `put_change(:edited_at, DateTime.utc_now())`.
  - `MessageReaction.changeset/2 :: %Ecto.Changeset{}` — casts `[:emoji, :message_id, :user_id]`, all required, single-grapheme emoji with `byte_size <= 16`, `unique_constraint([:message_id, :user_id, :emoji])`.
  - DB: `messages` columns `parent_message_id` (FK→messages, nullable, `on_delete: :delete_all`), `reply_count`, `last_reply_at`, `edited_at`, `deleted_at`, `also_sent_to_channel`; index `messages(parent_message_id, id)`.

---

- [ ] **Step 1: Write the failing test for the Message changesets**

  Create `test/phoenix_chat/chat/message_test.exs`:

  ```elixir
  defmodule PhoenixChat.Chat.MessageTest do
    use PhoenixChat.DataCase, async: true

    alias PhoenixChat.Chat.Message

    describe "changeset/2" do
      test "accepts body, parent_message_id and also_sent_to_channel; trims body" do
        cs =
          Message.changeset(%Message{}, %{
            "body" => "  a threaded reply  ",
            "parent_message_id" => 42,
            "also_sent_to_channel" => true
          })

        assert cs.valid?
        assert get_change(cs, :body) == "a threaded reply"
        assert get_change(cs, :parent_message_id) == 42
        assert get_change(cs, :also_sent_to_channel) == true
      end

      test "root messages need neither parent nor also_sent_to_channel" do
        cs = Message.changeset(%Message{}, %{body: "zdravo"})
        assert cs.valid?
        assert get_change(cs, :parent_message_id) == nil
        assert get_change(cs, :also_sent_to_channel) == nil
      end

      test "requires a non-blank body within 1..4000 chars" do
        assert %{body: ["can't be blank"]} =
                 errors_on(Message.changeset(%Message{}, %{body: "   "}))

        long = String.duplicate("x", 4001)

        assert %{body: ["should be at most 4000 character(s)"]} =
                 errors_on(Message.changeset(%Message{}, %{body: long}))
      end
    end

    describe "edit_changeset/2" do
      test "revalidates body and stamps edited_at" do
        before = DateTime.utc_now()
        cs = Message.edit_changeset(%Message{}, %{body: "  edited body  "})

        assert cs.valid?
        assert get_change(cs, :body) == "edited body"

        edited_at = get_change(cs, :edited_at)
        assert %DateTime{} = edited_at
        assert DateTime.compare(edited_at, before) in [:eq, :gt]
      end

      test "rejects a blank edit" do
        assert %{body: ["can't be blank"]} =
                 errors_on(Message.edit_changeset(%Message{}, %{body: "   "}))
      end
    end
  end
  ```

- [ ] **Step 2: Write the failing test for the MessageReaction changeset**

  Create `test/phoenix_chat/chat/message_reaction_test.exs`:

  ```elixir
  defmodule PhoenixChat.Chat.MessageReactionTest do
    use PhoenixChat.DataCase, async: true

    alias PhoenixChat.Chat.MessageReaction

    describe "changeset/2" do
      test "accepts any single-grapheme emoji (not just the old palette)" do
        for emoji <- ["👍", "🔥", "🤡", "🎉", "🇷🇸", "👍🏽"] do
          cs =
            MessageReaction.changeset(%MessageReaction{}, %{
              emoji: emoji,
              message_id: 1,
              user_id: 2
            })

          assert cs.valid?, "expected #{emoji} to be a valid reaction"
        end
      end

      test "requires emoji, message_id and user_id" do
        errors = errors_on(MessageReaction.changeset(%MessageReaction{}, %{}))
        assert errors.emoji == ["can't be blank"]
        assert errors.message_id == ["can't be blank"]
        assert errors.user_id == ["can't be blank"]
      end

      test "rejects multi-emoji or plain text" do
        assert %{emoji: ["must be a single emoji"]} =
                 errors_on(
                   MessageReaction.changeset(%MessageReaction{}, %{
                     emoji: "👍👍",
                     message_id: 1,
                     user_id: 2
                   })
                 )

        assert %{emoji: ["must be a single emoji"]} =
                 errors_on(
                   MessageReaction.changeset(%MessageReaction{}, %{
                     emoji: "lol",
                     message_id: 1,
                     user_id: 2
                   })
                 )
      end

      test "rejects an emoji whose byte size exceeds the cap" do
        # a 4-person ZWJ family is one grapheme but 25 bytes (> 16-byte cap)
        assert %{emoji: ["is too long"]} =
                 errors_on(
                   MessageReaction.changeset(%MessageReaction{}, %{
                     emoji: "👨‍👩‍👧‍👦",
                     message_id: 1,
                     user_id: 2
                   })
                 )
      end
    end
  end
  ```

- [ ] **Step 3: Run the new tests to verify they fail**

  ```
  mix test test/phoenix_chat/chat/message_test.exs test/phoenix_chat/chat/message_reaction_test.exs
  ```

  Expected: compilation fails / tests error because the referenced functions and fields do not exist yet — output contains
  `function PhoenixChat.Chat.Message.edit_changeset/2 is undefined or private` and
  `function PhoenixChat.Chat.MessageReaction.changeset/2 is undefined or private`
  (and, once those are added, the `changeset/2` case would still fail on `parent_message_id`/`also_sent_to_channel`). It does **not** print `0 failures`.

- [ ] **Step 4: Create the migration**

  Create `priv/repo/migrations/20260714120300_add_thread_edit_delete_to_messages.exs`:

  ```elixir
  defmodule PhoenixChat.Repo.Migrations.AddThreadEditDeleteToMessages do
    use Ecto.Migration

    def change do
      alter table(:messages) do
        add :parent_message_id, references(:messages, on_delete: :delete_all)
        add :reply_count, :integer, null: false, default: 0
        add :last_reply_at, :utc_datetime_usec
        add :edited_at, :utc_datetime_usec
        add :deleted_at, :utc_datetime_usec
        add :also_sent_to_channel, :boolean, null: false, default: false
      end

      create index(:messages, [:parent_message_id, :id])
    end
  end
  ```

- [ ] **Step 5: Apply the migration to the dev DB**

  ```
  mix ecto.migrate
  ```

  Expected: output shows `create index messages_parent_message_id_id_index` and
  `== Migrated 20260714120300 in 0.0s` with no errors. (The test DB is migrated automatically by the `test` alias — `ecto.create --quiet`, `ecto.migrate --quiet` — before every `mix test` run.)

- [ ] **Step 6: Update the Message schema**

  Replace the full contents of `lib/phoenix_chat/chat/message.ex` with:

  ```elixir
  defmodule PhoenixChat.Chat.Message do
    use Ecto.Schema
    import Ecto.Changeset

    schema "messages" do
      field :body, :string
      field :reply_count, :integer, default: 0
      field :last_reply_at, :utc_datetime_usec
      field :edited_at, :utc_datetime_usec
      field :deleted_at, :utc_datetime_usec
      field :also_sent_to_channel, :boolean, default: false

      belongs_to :channel, PhoenixChat.Chat.Channel
      belongs_to :user, PhoenixChat.Accounts.User
      belongs_to :parent, PhoenixChat.Chat.Message, foreign_key: :parent_message_id
      has_many :replies, PhoenixChat.Chat.Message, foreign_key: :parent_message_id
      has_many :reactions, PhoenixChat.Chat.MessageReaction

      timestamps(type: :utc_datetime_usec)
    end

    def changeset(message, attrs) do
      message
      |> cast(attrs, [:body, :parent_message_id, :also_sent_to_channel])
      |> update_change(:body, &String.trim/1)
      |> validate_required([:body])
      |> validate_length(:body, min: 1, max: 4000)
    end

    def edit_changeset(message, attrs) do
      message
      |> cast(attrs, [:body])
      |> update_change(:body, &String.trim/1)
      |> validate_required([:body])
      |> validate_length(:body, min: 1, max: 4000)
      |> put_change(:edited_at, DateTime.utc_now())
    end
  end
  ```

- [ ] **Step 7: Update the MessageReaction schema**

  Replace the full contents of `lib/phoenix_chat/chat/message_reaction.ex` with:

  ```elixir
  defmodule PhoenixChat.Chat.MessageReaction do
    use Ecto.Schema
    import Ecto.Changeset

    schema "message_reactions" do
      belongs_to :message, PhoenixChat.Chat.Message
      belongs_to :user, PhoenixChat.Accounts.User
      field :emoji, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    def changeset(reaction, attrs) do
      reaction
      |> cast(attrs, [:emoji, :message_id, :user_id])
      |> validate_required([:emoji, :message_id, :user_id])
      |> validate_emoji()
      |> unique_constraint([:message_id, :user_id, :emoji])
    end

    defp validate_emoji(changeset) do
      validate_change(changeset, :emoji, fn :emoji, emoji ->
        cond do
          length(String.graphemes(emoji)) != 1 -> [emoji: "must be a single emoji"]
          byte_size(emoji) > 16 -> [emoji: "is too long"]
          true -> []
        end
      end)
    end
  end
  ```

- [ ] **Step 8: Run the new tests — expect them green**

  ```
  mix test test/phoenix_chat/chat/message_test.exs test/phoenix_chat/chat/message_reaction_test.exs
  ```

  Expected: `0 failures` (7 tests).

- [ ] **Step 9: Run the full suite to confirm no regressions**

  ```
  mix test
  ```

  Expected: `0 failures`. The new `messages` columns are present in the test DB (migrated by the `test` alias), so existing `Chat.send_message/3`, `list_messages/2`, and reaction tests continue to pass unchanged — `changeset/2` still ignores unrelated attrs and the old `toggle_reaction/3` palette guard is untouched until Task 4.

- [ ] **Step 10: Commit**

  ```
  git add priv/repo/migrations/20260714120300_add_thread_edit_delete_to_messages.exs \
    lib/phoenix_chat/chat/message.ex \
    lib/phoenix_chat/chat/message_reaction.ex \
    test/phoenix_chat/chat/message_test.exs \
    test/phoenix_chat/chat/message_reaction_test.exs
  git commit -m "Add message thread/edit/delete columns and reaction changeset" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 4: Chat context — threads (send reply, list replies, timeline filter)

**Files:**
- Modify: `lib/phoenix_chat/chat.ex` (anchor by `send_message/3`, `list_messages/2`; add private `validate_parent/2` and public `list_thread_replies/2`)
- Test: `test/phoenix_chat/chat_test.exs` (add a new `describe "threads"` block)

**Interfaces:**
- Consumes:
  - `PhoenixChat.Chat.Message` schema with fields `parent_message_id`, `reply_count` (default `0`), `last_reply_at`, `also_sent_to_channel` (default `false`) — added in Task 3.
  - `PhoenixChat.Chat.Message.changeset/2` casting `[:body, :parent_message_id, :also_sent_to_channel]` (trim + len 1..4000 on `body`) — Task 3.
  - Existing helpers `get_message!/1 :: %Message{user, reactions}`, `broadcast!/2`, `topic/1`, `member?/2`.
  - Fixtures `message_fixture/2,3`, `channel_fixture/1,2`, `user_fixture/0`.
- Produces:
  - `send_message/3` — when `attrs` carries `parent_message_id`: validate parent exists & same channel; insert reply; `Repo.update_all(inc: [reply_count: 1], set: [last_reply_at: now])` on parent; broadcast `{:new_message, reply}` AND `{:message_updated, reloaded_parent}`. Returns `{:ok, %Message{user, reactions: []}} | {:error, cs} | {:error, :not_a_member}`.
  - `list_thread_replies/2 :: (%Message{}, opts) -> {[%Message{user, reactions}], cursor}` — ascending, `:limit`/`:before_id`.
  - `list_messages/2` timeline filtered by `is_nil(m.parent_message_id) or m.also_sent_to_channel == true`.

---

- [ ] **Step 1: Write the failing tests** — append a new `describe "threads"` block to `test/phoenix_chat/chat_test.exs`, immediately after the closing `end` of the `describe "messages" do … end` block (before `describe "unread tracking"`). Complete code:

```elixir
  describe "threads" do
    setup do
      user = user_fixture()
      channel = channel_fixture(user)
      parent = message_fixture(user, channel, %{body: "korijen"})
      %{user: user, channel: channel, parent: parent}
    end

    test "reply sets parent_message_id, bumps parent count/last_reply_at, broadcasts both", %{
      user: user,
      channel: channel,
      parent: parent
    } do
      :ok = Chat.subscribe(channel)

      assert {:ok, reply} =
               Chat.send_message(user, channel, %{body: "odgovor", parent_message_id: parent.id})

      assert reply.parent_message_id == parent.id

      reloaded = Chat.get_message!(parent.id)
      assert reloaded.reply_count == 1
      assert reloaded.last_reply_at != nil

      assert_receive {:new_message, %{id: rid, parent_message_id: pid}}
      assert rid == reply.id
      assert pid == parent.id

      assert_receive {:message_updated, %{id: parent_id, reply_count: 1, last_reply_at: last}}
      assert parent_id == parent.id
      assert last != nil
    end

    test "list_thread_replies/2 paginates ascending with cursor", %{
      user: user,
      channel: channel,
      parent: parent
    } do
      for i <- 1..7 do
        message_fixture(user, channel, %{body: "r#{i}", parent_message_id: parent.id})
      end

      {page, cursor} = Chat.list_thread_replies(parent, limit: 5)
      assert Enum.map(page, & &1.body) == for(i <- 3..7, do: "r#{i}")
      assert cursor == List.first(page).id

      {older, older_cursor} = Chat.list_thread_replies(parent, limit: 5, before_id: cursor)
      assert Enum.map(older, & &1.body) == ["r1", "r2"]
      assert older_cursor == nil
    end

    test "list_messages/2 excludes plain replies but includes also_sent_to_channel ones", %{
      user: user,
      channel: channel,
      parent: parent
    } do
      {:ok, hidden} =
        Chat.send_message(user, channel, %{body: "skriven", parent_message_id: parent.id})

      {:ok, shown} =
        Chat.send_message(user, channel, %{
          body: "vidljiv",
          parent_message_id: parent.id,
          also_sent_to_channel: true
        })

      {timeline, _cursor} = Chat.list_messages(channel)
      ids = Enum.map(timeline, & &1.id)

      assert parent.id in ids
      refute hidden.id in ids
      assert shown.id in ids
    end

    test "reply to a parent in another channel is rejected", %{user: user, parent: parent} do
      other_channel = channel_fixture(user)

      assert {:error, cs} =
               Chat.send_message(user, other_channel, %{
                 body: "krivi kanal",
                 parent_message_id: parent.id
               })

      assert "does not belong to this channel" in errors_on(cs).parent_message_id
    end
  end
```

- [ ] **Step 2: Run to verify it fails** — command:

```
mix test test/phoenix_chat/chat_test.exs
```

Expected: the 4 new `threads` tests fail. Representative failures:
- `list_thread_replies/2` test raises `** (UndefinedFunctionError) function PhoenixChat.Chat.list_thread_replies/2 is undefined or private`.
- "reply sets parent_message_id …" fails — `reloaded.reply_count == 1` gets `0` (parent never bumped) and `assert_receive {:message_updated, …}` times out (only `{:new_message}` is broadcast today).
- "excludes plain replies …" fails on `refute hidden.id in ids` (current `list_messages/2` returns every message including replies).
- "reply to a parent in another channel is rejected" fails with a `MatchError` on `{:error, cs}` (today the reply inserts successfully with no same-channel guard).

- [ ] **Step 3: Implement the thread behavior in `lib/phoenix_chat/chat.ex`.**

Replace the whole `send_message/3` function (currently under the `## Messages` section) with the version below, and add the private `validate_parent/2` directly after it:

```elixir
  def send_message(%User{} = user, %Channel{} = channel, attrs) do
    if member?(user, channel) do
      changeset = Message.changeset(%Message{user_id: user.id, channel_id: channel.id}, attrs)

      with {:ok, changeset} <- validate_parent(changeset, channel),
           {:ok, message} <- Repo.insert(changeset) do
        message = %{message | user: user, reactions: []}

        case message.parent_message_id do
          nil ->
            broadcast!(channel, {:new_message, message})
            {:ok, message}

          parent_id ->
            now = DateTime.utc_now()

            from(m in Message, where: m.id == ^parent_id)
            |> Repo.update_all(inc: [reply_count: 1], set: [last_reply_at: now])

            broadcast!(channel, {:new_message, message})
            broadcast!(channel, {:message_updated, get_message!(parent_id)})
            {:ok, message}
        end
      end
    else
      {:error, :not_a_member}
    end
  end

  defp validate_parent(changeset, %Channel{} = channel) do
    case Ecto.Changeset.get_change(changeset, :parent_message_id) do
      nil ->
        {:ok, changeset}

      parent_id ->
        if Repo.exists?(
             from m in Message, where: m.id == ^parent_id and m.channel_id == ^channel.id
           ) do
          {:ok, changeset}
        else
          {:error,
           Ecto.Changeset.add_error(
             changeset,
             :parent_message_id,
             "does not belong to this channel"
           )}
        end
    end
  end
```

Add `list_thread_replies/2` immediately after `list_messages/2` (still within the `## Messages` section):

```elixir
  @doc """
  Replies to a thread parent in ascending order plus a cursor for older pages.
  Cursor is nil when there is nothing older.
  """
  def list_thread_replies(%Message{} = parent, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before_id)

    query =
      from m in Message,
        where: m.parent_message_id == ^parent.id,
        order_by: [desc: m.id],
        limit: ^limit,
        preload: [:user, :reactions]

    query = if before_id, do: where(query, [m], m.id < ^before_id), else: query

    messages = query |> Repo.all() |> Enum.reverse()

    cursor =
      if length(messages) == limit, do: List.first(messages).id, else: nil

    {messages, cursor}
  end
```

Modify `list_messages/2` — add the thread filter as a second `where:` in its `from` query. Replace:

```elixir
    query =
      from m in Message,
        where: m.channel_id == ^channel.id,
        order_by: [desc: m.id],
        limit: ^limit,
        preload: [:user, :reactions]
```

with:

```elixir
    query =
      from m in Message,
        where: m.channel_id == ^channel.id,
        where: is_nil(m.parent_message_id) or m.also_sent_to_channel == true,
        order_by: [desc: m.id],
        limit: ^limit,
        preload: [:user, :reactions]
```

- [ ] **Step 4: Run tests** — command:

```
mix test test/phoenix_chat/chat_test.exs
```

Expected: `0 failures` — every test in the file passes, including the 4 new `threads` tests. Then run the full suite to confirm no regression in the timeline filter or fixtures:

```
mix test
```

Expected: `0 failures`.

- [ ] **Step 5: Commit.**

```
git add lib/phoenix_chat/chat.ex test/phoenix_chat/chat_test.exs
git commit -m "Add message threads to Chat context" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Chat context — edit, soft-delete, arbitrary-emoji reactions, root-only unread

**Files:**
- Modify: `lib/phoenix_chat/chat.ex` (add `update_message/3` + `delete_message/2` in the `## Messages` section after `list_messages/2`; relax `toggle_reaction/3`; add `is_nil(parent_message_id)` to `memberships_with_unread/2` and `unread_count/2`)
- Test: `test/phoenix_chat/chat_test.exs` (new `describe "update_message/3 and delete_message/2"`; rework the `describe "reactions"` palette test; add one test to `describe "unread tracking"`)

**Interfaces:**
- Consumes:
  - `PhoenixChat.Chat.Message` fields `edited_at :: utc_datetime_usec`, `deleted_at :: utc_datetime_usec`, `parent_message_id` (Task 3)
  - `Message.edit_changeset(message, attrs) :: Ecto.Changeset` — casts `[:body]`, validates body (trim, 1..4000), `put_change(:edited_at, now)` (Task 3)
  - `MessageReaction.changeset(struct, attrs) :: Ecto.Changeset` — casts `[:emoji, :message_id, :user_id]`, required all, single-grapheme emoji `byte_size <= 16`, `unique_constraint([:message_id, :user_id, :emoji])` (Task 3)
  - `Chat.send_message/3` accepting `parent_message_id` in attrs (Task 4 parent handling; also persists via Task 3's `Message.changeset` cast) — used only in the unread test to create a reply
  - Existing helpers: `get_message!/1`, `get_channel!/1`, `member?/2`, `broadcast!/2` (topic `"chat:channel:#{id}"`), `subscribe/1`; `reaction_palette/0` and `summarize_reactions/2` stay unchanged
- Produces:
  - `Chat.update_message(%User{}, %Message{}, attrs) :: {:ok, %Message{}} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}` — author-only, stamps `edited_at`, broadcasts `{:message_updated, msg}`
  - `Chat.delete_message(%User{}, %Message{}) :: {:ok, %Message{}} | {:error, :unauthorized}` — author-only soft delete (`deleted_at`), keeps replies, broadcasts `{:message_deleted, msg}`
  - `Chat.toggle_reaction(%User{}, %Message{}, emoji :: String.t()) :: :ok | {:error, :invalid_emoji} | {:error, :not_a_member}` — now accepts any valid single-grapheme emoji, still membership-gated, broadcasts `{:reaction_changed, msg}`
  - `Chat.unread_count/2` and `Chat.list_joined_channels/1` count only root messages (`is_nil(parent_message_id)`)

---

- [ ] **Step 1: Write the failing edit/delete tests.** In `test/phoenix_chat/chat_test.exs`, add a new `describe` block immediately after the closing `end` of the existing `describe "messages" do` block (before `describe "unread tracking"`):

```elixir
  describe "update_message/3 and delete_message/2" do
    setup do
      author = user_fixture()
      channel = channel_fixture(author)
      message = message_fixture(author, channel)
      %{author: author, channel: channel, message: message}
    end

    test "update_message/3 edits the body, stamps edited_at, and broadcasts", %{
      author: author,
      channel: channel,
      message: message
    } do
      :ok = Chat.subscribe(channel)

      assert {:ok, updated} = Chat.update_message(author, message, %{body: "izmenjeno"})
      assert updated.body == "izmenjeno"
      assert updated.edited_at
      assert updated.user.id == author.id

      assert_receive {:message_updated, %{id: id, body: "izmenjeno", edited_at: edited_at}}
      assert id == message.id
      assert edited_at
    end

    test "update_message/3 rejects a non-author", %{message: message} do
      stranger = user_fixture()
      assert {:error, :unauthorized} = Chat.update_message(stranger, message, %{body: "upad"})
      assert Chat.get_message!(message.id).body == message.body
    end

    test "update_message/3 validates the body", %{author: author, message: message} do
      too_long = String.duplicate("x", 4001)
      assert {:error, cs} = Chat.update_message(author, message, %{body: too_long})
      assert "should be at most 4000 character(s)" in errors_on(cs).body
    end

    test "delete_message/2 soft-deletes, keeps the row, and broadcasts", %{
      author: author,
      channel: channel,
      message: message
    } do
      :ok = Chat.subscribe(channel)

      assert {:ok, deleted} = Chat.delete_message(author, message)
      assert deleted.deleted_at

      # soft delete: the row is retained
      assert Chat.get_message!(message.id).deleted_at

      assert_receive {:message_deleted, %{id: id, deleted_at: deleted_at}}
      assert id == message.id
      assert deleted_at
    end

    test "delete_message/2 rejects a non-author", %{message: message} do
      stranger = user_fixture()
      assert {:error, :unauthorized} = Chat.delete_message(stranger, message)
      refute Chat.get_message!(message.id).deleted_at
    end
  end
```

- [ ] **Step 2: Run to verify it fails.** Run:

```
mix test test/phoenix_chat/chat_test.exs
```

Expected: the 5 new tests fail with `** (UndefinedFunctionError) function PhoenixChat.Chat.update_message/3 is undefined or private` (and `.../delete_message/2 is undefined`). Preceded by compiler warnings `PhoenixChat.Chat.update_message/3 is undefined`. All pre-existing tests still pass.

- [ ] **Step 3: Implement `update_message/3` and `delete_message/2`.** In `lib/phoenix_chat/chat.ex`, in the `## Messages` section, immediately after the `list_messages/2` function (right before the `## Unread` comment), add:

```elixir
  @doc """
  Edits a message's body. Author-only: returns `{:error, :unauthorized}` for
  anyone else. On success stamps `edited_at` (via `Message.edit_changeset/2`)
  and broadcasts `{:message_updated, message}` with `:user`/`:reactions` reloaded.
  """
  def update_message(%User{} = user, %Message{} = message, attrs) do
    if message.user_id == user.id do
      changeset = Message.edit_changeset(message, attrs)

      with {:ok, _} <- Repo.update(changeset) do
        updated = get_message!(message.id)
        broadcast!(get_channel!(message.channel_id), {:message_updated, updated})
        {:ok, updated}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Soft-deletes a message. Author-only: returns `{:error, :unauthorized}` for
  anyone else. Sets `deleted_at`; the row and any thread replies are retained.
  Broadcasts `{:message_deleted, message}` so clients render a tombstone.
  """
  def delete_message(%User{} = user, %Message{} = message) do
    if message.user_id == user.id do
      from(m in Message, where: m.id == ^message.id)
      |> Repo.update_all(set: [deleted_at: DateTime.utc_now()])

      deleted = get_message!(message.id)
      broadcast!(get_channel!(message.channel_id), {:message_deleted, deleted})
      {:ok, deleted}
    else
      {:error, :unauthorized}
    end
  end
```

- [ ] **Step 4: Run tests.** Run:

```
mix test test/phoenix_chat/chat_test.exs
```

Expected: `0 failures` — the 5 edit/delete tests now pass and every pre-existing test still passes (reactions + unread are untouched so far).

- [ ] **Step 5: Rework the reaction palette test into arbitrary-emoji tests.** In `test/phoenix_chat/chat_test.exs`, inside `describe "reactions"`, replace the existing out-of-palette test:

```elixir
    test "rejects emoji outside the palette", %{user: user, message: message} do
      assert {:error, :invalid_emoji} = Chat.toggle_reaction(user, message, "🤡")
    end
```

with these two tests:

```elixir
    test "accepts an arbitrary emoji outside the quick palette", %{
      user: user,
      channel: channel,
      message: message
    } do
      :ok = Chat.subscribe(channel)

      assert :ok = Chat.toggle_reaction(user, message, "🤡")
      assert_receive {:reaction_changed, %{id: mid, reactions: [%{emoji: "🤡"}]}}
      assert mid == message.id

      # toggling the same arbitrary emoji removes it
      assert :ok = Chat.toggle_reaction(user, message, "🤡")
      assert_receive {:reaction_changed, %{reactions: []}}
    end

    test "rejects an invalid emoji via the changeset", %{user: user, message: message} do
      assert {:error, :invalid_emoji} = Chat.toggle_reaction(user, message, "not an emoji")
    end
```

- [ ] **Step 6: Run to verify it fails.** Run:

```
mix test test/phoenix_chat/chat_test.exs
```

Expected: `"accepts an arbitrary emoji outside the quick palette"` fails on the first assertion —

```
match (=) failed
code:  assert :ok = Chat.toggle_reaction(user, message, "🤡")
right: {:error, :invalid_emoji}
```

because the current `toggle_reaction/3` still guards on the fixed `@reaction_palette`. The other reaction/edit/delete tests pass.

- [ ] **Step 7: Relax `toggle_reaction/3`.** In `lib/phoenix_chat/chat.ex`, in the `## Reactions` section, replace the two existing `toggle_reaction/3` clauses (the `when emoji in @reaction_palette` clause and the `{:error, :invalid_emoji}` fallback clause) with a single clause that validates through `MessageReaction.changeset/2`:

```elixir
  def toggle_reaction(%User{} = user, %Message{} = message, emoji) do
    channel = get_channel!(message.channel_id)

    changeset =
      MessageReaction.changeset(%MessageReaction{}, %{
        emoji: emoji,
        message_id: message.id,
        user_id: user.id
      })

    cond do
      not member?(user, channel) ->
        {:error, :not_a_member}

      not changeset.valid? ->
        {:error, :invalid_emoji}

      true ->
        case Repo.get_by(MessageReaction,
               message_id: message.id,
               user_id: user.id,
               emoji: emoji
             ) do
          nil -> Repo.insert!(changeset)
          %MessageReaction{} = reaction -> Repo.delete!(reaction)
        end

        broadcast!(channel, {:reaction_changed, get_message!(message.id)})
        :ok
    end
  end
```

Leave `reaction_palette/0`, the `@reaction_palette` module attribute, and `summarize_reactions/2` unchanged — the palette stays as the UI quick-access shortlist.

- [ ] **Step 8: Run tests.** Run:

```
mix test test/phoenix_chat/chat_test.exs
```

Expected: `0 failures`. `"👍"` still toggles and dedups, `"🤡"` is now accepted and toggles, `"not an emoji"` is rejected as `{:error, :invalid_emoji}`, non-members still get `{:error, :not_a_member}`, and `summarize_reactions/2` (palette-only) still passes.

- [ ] **Step 9: Write the failing root-only unread test.** In `test/phoenix_chat/chat_test.exs`, inside `describe "unread tracking"`, add this test after the existing `"unread_count/2 is 0 for non-members"` test:

```elixir
    test "thread replies do not increment channel unread (root messages only)" do
      me = user_fixture()
      other = user_fixture()
      channel = channel_fixture(me)
      {:ok, _} = Chat.join_channel(other, channel)

      {:ok, root} = Chat.send_message(other, channel, %{body: "korenska"})
      # a reply carries parent_message_id and must NOT count toward unread
      {:ok, _reply} =
        Chat.send_message(other, channel, %{body: "odgovor", parent_message_id: root.id})

      assert Chat.unread_count(me, channel) == 1

      assert %{unread: 1} =
               Enum.find(Chat.list_joined_channels(me), &(&1.channel.id == channel.id))
    end
```

- [ ] **Step 10: Run to verify it fails.** Run:

```
mix test test/phoenix_chat/chat_test.exs
```

Expected: the new test fails on the count —

```
Assertion with == failed
code:  assert Chat.unread_count(me, channel) == 1
left:  2
right: 1
```

because the current unread queries count every non-own message (root **and** reply). All other tests pass.

- [ ] **Step 11: Make unread root-only.** In `lib/phoenix_chat/chat.ex`, add `and is_nil(...)` on the `parent_message_id` to both unread queries.

Replace `memberships_with_unread/2` with:

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
            msg.user_id != ^user.id and is_nil(msg.parent_message_id),
        group_by: c.id,
        order_by: [asc: c.name],
        select: %{channel: c, unread: count(msg.id)}
    )
  end
```

Replace `unread_count/2` with:

```elixir
  def unread_count(%User{} = user, %Channel{} = channel) do
    case Repo.get_by(ChannelMembership, user_id: user.id, channel_id: channel.id) do
      nil ->
        0

      %ChannelMembership{last_read_at: last_read_at} ->
        Repo.aggregate(
          from(m in Message,
            where:
              m.channel_id == ^channel.id and m.inserted_at > ^last_read_at and
                m.user_id != ^user.id and is_nil(m.parent_message_id)
          ),
          :count
        )
    end
  end
```

- [ ] **Step 12: Run tests.** Run:

```
mix test test/phoenix_chat/chat_test.exs
```

Expected: `0 failures`. The reply no longer counts (`unread == 1`), and the pre-existing `"unread counts exclude own messages and reset on mark_read"` test still passes (its messages are all root messages).

- [ ] **Step 13: Run the full suite.** Run:

```
mix test
```

Expected: the whole suite is green — `... 0 failures` (edit/delete, arbitrary-emoji reactions, and root-only unread all pass alongside every prior task's tests).

- [ ] **Step 14: Commit.** Run:

```
git add lib/phoenix_chat/chat.ex test/phoenix_chat/chat_test.exs
git commit -m "Add message edit, soft-delete, arbitrary-emoji reactions, root-only unread" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Markdown rendering (MDEx, sanitized)

**Files:**
- Modify: `mix.exs` (anchor: `deps/0` — add the `:mdex` dependency)
- Create: `lib/phoenix_chat/markdown.ex`
- Modify: `lib/phoenix_chat_web/live/chat_live/components.ex` (anchor: `message_entry/1` — the `data-msg-body` element)
- Test: `test/phoenix_chat/markdown_test.exs`

**Interfaces:**
- Consumes: `PhoenixChatWeb.ChatComponents.message_entry/1` assign `@entry.body :: String.t()` (built in `PhoenixChatWeb.ChatLive`); `MDEx.to_html!/2`; `MDEx.Document.default_sanitize_options/0`; `Phoenix.HTML.raw/1`.
- Produces: `PhoenixChat.Markdown.render(body :: String.t()) :: Phoenix.HTML.safe()` — sanitized, Slack-lite HTML safe tuple `{:safe, iodata}`.

**Design notes (verified against hexdocs.pm/mdex, v0.13.3):**
- `MDEx.to_html!/2` accepts `extension:`, `render:`, `sanitize:` option keys.
- `:sanitize` takes `sanitize_options() | nil` — **not** a boolean; use `MDEx.Document.default_sanitize_options/0` (a keyword list with `:tags`, `:rm_tags`, `:link_rel: "noopener noreferrer"`, `:url_schemes`, `:strip_comments`, etc.).
- The default allow-list permits `img` and `table`; Slack-lite strips both via the `:rm_tags` key. Markdown pipe-tables are already inert because the `table` extension is left off; `img` must be removed explicitly.
- `render: [unsafe: true]` passes raw HTML into the sanitizer so `<script>` (a default clean-content tag) is dropped content-and-all, and disallowed tags (`<iframe>`, etc.) are removed — rather than being escaped to visible text.
- MDEx ships a precompiled NIF (rustler_precompiled); `aarch64-apple-darwin` is a supported target, so no Rust toolchain is needed.

---

- [ ] **Step 1: Write the failing test**

Create `test/phoenix_chat/markdown_test.exs`:

```elixir
defmodule PhoenixChat.MarkdownTest do
  use ExUnit.Case, async: true

  alias PhoenixChat.Markdown

  defp html(body), do: body |> Markdown.render() |> Phoenix.HTML.safe_to_string()

  describe "render/1" do
    test "returns a Phoenix.HTML safe tuple" do
      assert {:safe, _iodata} = Markdown.render("hello")
    end

    test "renders strong emphasis" do
      assert html("**bold**") =~ "<strong>bold</strong>"
    end

    test "renders regular emphasis" do
      assert html("_italic_") =~ "<em>italic</em>"
    end

    test "renders strikethrough" do
      assert html("~~gone~~") =~ "<del>gone</del>"
    end

    test "renders inline code" do
      assert html("`inline`") =~ "<code>inline</code>"
    end

    test "renders fenced code blocks" do
      out = html("```\nline\n```")
      assert out =~ "<pre>"
      assert out =~ "<code"
      assert out =~ "line"
    end

    test "renders explicit links" do
      out = html("[Elixir](https://elixir-lang.org)")
      assert out =~ ~s(href="https://elixir-lang.org")
      assert out =~ ">Elixir</a>"
    end

    test "autolinks bare urls" do
      assert html("see https://elixir-lang.org now") =~ ~s(href="https://elixir-lang.org")
    end

    test "renders blockquotes and lists" do
      assert html("> quote") =~ "<blockquote>"
      assert html("- one\n- two") =~ "<li>one</li>"
    end

    test "strips <script> tags via sanitize" do
      out = html("hi <script>alert('xss')</script>")
      refute out =~ "<script"
      refute out =~ "alert('xss')"
      assert out =~ "hi"
    end

    test "strips raw inline HTML such as <iframe>" do
      refute html(~s(<iframe src="https://evil.test"></iframe>)) =~ "<iframe"
    end

    test "strips images" do
      refute html("![alt](https://example.test/x.png)") =~ "<img"
    end

    test "does not render markdown tables" do
      refute html("| a | b |\n| - | - |\n| 1 | 2 |") =~ "<table"
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```bash
mix test test/phoenix_chat/markdown_test.exs
```

Expected failure: every test errors with `** (UndefinedFunctionError) function PhoenixChat.Markdown.render/1 is undefined (module PhoenixChat.Markdown is not available)` — reported as `13 tests, 13 failures`.

- [ ] **Step 3: Add the `:mdex` dependency to `mix.exs`**

In `deps/0`, insert the `:mdex` line immediately after the `:jason` entry. Change:

```elixir
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
```

to:

```elixir
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:mdex, "~> 0.13"},
      {:dns_cluster, "~> 0.2.0"},
```

- [ ] **Step 4: Fetch the dependency**

```bash
mix deps.get
```

Expected output resolves and locks the new package (and its precompiled-NIF helper), e.g.:

```
Resolving Hex dependencies...
Resolution completed in ...
New:
  mdex 0.13.3
  rustler_precompiled 0.8.x
* Getting mdex (Hex package)
* Getting rustler_precompiled (Hex package)
```

(`mix.lock` is updated. The MDEx precompiled NIF is downloaded on the first compile in Step 6.)

- [ ] **Step 5: Implement `PhoenixChat.Markdown`**

Create `lib/phoenix_chat/markdown.ex`:

```elixir
defmodule PhoenixChat.Markdown do
  @moduledoc """
  Slack-lite Markdown rendering backed by MDEx.

  Supports emphasis, strong, strikethrough, inline and fenced code,
  blockquotes, lists and autolinks. Raw HTML, images and tables are
  stripped so message bodies can never inject markup.
  """

  # Tags the default sanitizer allows that we deliberately drop for Slack-lite.
  @blocked_tags ~w(img table thead tbody tr td th)

  @extension [strikethrough: true, autolink: true]
  @render [unsafe: true]

  @doc """
  Renders `body` to sanitized, safe HTML.

  Returns a `t:Phoenix.HTML.safe/0` tuple ready to interpolate in a HEEx
  template. Raw HTML is parsed and then cleaned by the sanitizer, so
  disallowed markup (scripts, images, tables, iframes, ...) is removed
  rather than escaped.
  """
  def render(body) when is_binary(body) do
    body
    |> MDEx.to_html!(extension: @extension, render: @render, sanitize: sanitize_options())
    |> Phoenix.HTML.raw()
  end

  defp sanitize_options do
    MDEx.Document.default_sanitize_options()
    |> Keyword.update(:rm_tags, @blocked_tags, &(&1 ++ @blocked_tags))
  end
end
```

- [ ] **Step 6: Run the Markdown tests**

```bash
mix test test/phoenix_chat/markdown_test.exs
```

(The first run compiles MDEx and downloads its precompiled NIF.) Expected: `Finished in ...` / `13 tests, 0 failures`.

- [ ] **Step 7: Wire `render/1` into the message body**

In `lib/phoenix_chat_web/live/chat_live/components.ex`, inside `message_entry/1`, replace the plain-text body element. Change:

```heex
          <p data-msg-body class="whitespace-pre-wrap break-words text-sm text-foreground">
            {@entry.body}
          </p>
```

to:

```heex
          <div data-msg-body class="whitespace-pre-wrap break-words text-sm text-foreground">
            {PhoenixChat.Markdown.render(@entry.body)}
          </div>
```

(`{...}` renders the `{:safe, _}` tuple without re-escaping; the element becomes a `div` so MDEx block output like `<p>`/`<ul>` nests validly, and `whitespace-pre-wrap` still preserves soft line breaks in plain multi-line messages.)

- [ ] **Step 8: Run the full suite with warnings as errors**

```bash
mix compile --warning-as-errors && mix test
```

Expected: clean compile (no undefined-function warning for `PhoenixChat.Markdown`) and `0 failures`. Existing `chat_live_test.exs` assertions such as `render(view) =~ "prva poruka"` still match because the plain text remains a substring inside the rendered `<p>prva poruka</p>`.

- [ ] **Step 9: Commit**

```bash
git add mix.exs mix.lock lib/phoenix_chat/markdown.ex lib/phoenix_chat_web/live/chat_live/components.ex test/phoenix_chat/markdown_test.exs
git commit -m "Add sanitized Slack-lite Markdown rendering" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Emoji dataset + PhoenixChat.Emoji + EmojiPickerComponent

Vendor a real emoji dataset, expose it through a compile-time `PhoenixChat.Emoji` catalog (`all/0`, `categories/0`, `search/1`), and build the reusable `PhoenixChatWeb.EmojiPickerComponent` (search box + category tabs + grid) that bubbles an `"emoji_picked"` event to its parent LiveView. `Chat.reaction_palette/0` stays unchanged — it remains the quick-access row; wiring the "＋"-opens-picker affordance into the message toolbar and composer belongs to the ChatLive UI tasks, so this task ships only the dataset, the module, and the component, plus their tests, without touching `ChatLive` (avoids collisions with the concurrent UI tasks).

**Dataset source & license.** `github/gemoji` — `https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json` — **MIT License** (emoji names derived from the Unicode CLDR). 1870 entries; each is `{"emoji","description","category","aliases","tags", ...}`. We map `emoji→char`, `description→name`, `category→category`, and `aliases ++ tags→keywords`.

**Files:**
- Create: `priv/emoji/emoji.json` (vendored gemoji dataset)
- Create: `lib/phoenix_chat/emoji.ex` (module `PhoenixChat.Emoji`)
- Create: `lib/phoenix_chat_web/components/emoji_picker_component.ex` (module `PhoenixChatWeb.EmojiPickerComponent`)
- Test: `test/phoenix_chat/emoji_test.exs`
- Test: `test/phoenix_chat_web/components/emoji_picker_component_test.exs`

**Interfaces:**
- Consumes: `Chat.reaction_palette/0` (kept, no change); `use PhoenixChatWeb, :live_component` / `:live_view` (bare Phoenix modules, no app layout); `Jason` (compile-time decode).
- Produces:
  - `PhoenixChat.Emoji.all/0 :: [%{char: String.t(), name: String.t(), category: String.t(), keywords: [String.t()]}]`
  - `PhoenixChat.Emoji.categories/0 :: [String.t()]`
  - `PhoenixChat.Emoji.search/1 :: (String.t()) -> [%{char,name,category,keywords}]` (case-insensitive substring over name+keywords; blank → `all/0`)
  - `PhoenixChatWeb.EmojiPickerComponent` — LiveComponent; assigns `id` (required), `target` (`:reaction | :composer`, required), `message_id` (optional). Emoji pick buttons emit the **parent** event `"emoji_picked"` with `%{"emoji" => char, "target" => to_string(target), "message-id" => id | absent}`.

---

- [ ] **Step 1: Write the failing `PhoenixChat.Emoji` test**

Create `test/phoenix_chat/emoji_test.exs` (plain ExUnit — the catalog has no DB):

```elixir
defmodule PhoenixChat.EmojiTest do
  use ExUnit.Case, async: true

  alias PhoenixChat.Emoji

  test "all/0 returns %{char, name, category, keywords} maps" do
    grinning = Enum.find(Emoji.all(), &(&1.char == "😀"))

    assert %{
             char: "😀",
             name: "grinning face",
             category: "Smileys & Emotion",
             keywords: keywords
           } = grinning

    assert is_list(keywords)
    assert "grinning" in keywords
  end

  test "categories/0 lists the Unicode groups without duplicates" do
    categories = Emoji.categories()

    assert "Smileys & Emotion" in categories
    assert "Flags" in categories
    assert categories == Enum.uniq(categories)
  end

  test "search/1 finds an emoji by its name" do
    results = Emoji.search("grinning")

    assert Enum.any?(results, &(&1.char == "😀"))
  end

  test "search/1 finds an emoji by a keyword absent from its name" do
    # 🎉 is "party popper"; the word "tada" appears only in its aliases.
    results = Emoji.search("tada")

    assert Enum.any?(results, &(&1.char == "🎉"))
    refute Enum.any?(results, &String.contains?(&1.name, "tada"))
  end

  test "search/1 is case-insensitive" do
    assert Emoji.search("GRINNING") == Emoji.search("grinning")
  end

  test "search/1 with a blank query returns the whole catalog" do
    assert Emoji.search("   ") == Emoji.all()
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```
mix test test/phoenix_chat/emoji_test.exs
```

Expected: `6 tests, 6 failures`, each erroring with
`** (UndefinedFunctionError) function PhoenixChat.Emoji.all/0 is undefined (module PhoenixChat.Emoji is not available)` (and the same for `categories/0`, `search/1`).

- [ ] **Step 3: Vendor the emoji dataset**

Download the gemoji dataset into `priv/emoji/emoji.json`:

```
mkdir -p priv/emoji
curl -fsSL https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json -o priv/emoji/emoji.json
```

Verify it landed (should be ~1870 entries):

```
grep -c '"emoji"' priv/emoji/emoji.json
```

Expected: `1870` (a value ≥ 1500 is acceptable if gemoji has since grown). Each object has string keys `emoji`, `description`, `category`, and arrays `aliases`, `tags`.

- [ ] **Step 4: Implement `PhoenixChat.Emoji`**

Create `lib/phoenix_chat/emoji.ex`. The dataset is read at **compile time** via a `__DIR__`-relative path (robust — no dependency on `_build`) and registered as an `@external_resource` so edits to the JSON trigger recompilation. A precomputed lowercase haystack index keeps `search/1` allocation-free per keystroke:

```elixir
defmodule PhoenixChat.Emoji do
  @moduledoc """
  Compile-time emoji catalog vendored from the gemoji dataset
  (`priv/emoji/emoji.json`, github/gemoji, MIT License).

  Each entry is a `%{char, name, category, keywords}` map. `search/1` does a
  case-insensitive substring match over each emoji's name and keywords. The
  file is read once at compile time and embedded in the module, so lookups do
  no I/O at runtime.
  """

  # Resolve relative to this source file (lib/phoenix_chat/emoji.ex) so the
  # path holds during compilation, before any _build/.app exists.
  @emoji_path Path.join([__DIR__, "..", "..", "priv", "emoji", "emoji.json"])
  @external_resource @emoji_path

  @emojis @emoji_path
          |> File.read!()
          |> Jason.decode!()
          |> Enum.map(fn entry ->
            %{
              char: entry["emoji"],
              name: entry["description"],
              category: entry["category"],
              keywords: Enum.uniq((entry["aliases"] || []) ++ (entry["tags"] || []))
            }
          end)

  @categories @emojis |> Enum.map(& &1.category) |> Enum.uniq()

  # {lowercased "name keyword keyword …" haystack, emoji} pairs, in dataset order.
  @index Enum.map(@emojis, fn emoji ->
           haystack =
             [emoji.name | emoji.keywords]
             |> Enum.join(" ")
             |> String.downcase()

           {haystack, emoji}
         end)

  @doc "All vendored emoji as `%{char, name, category, keywords}` maps, in dataset order."
  def all, do: @emojis

  @doc "Distinct emoji categories, in dataset order."
  def categories, do: @categories

  @doc """
  Case-insensitive substring search over each emoji's name and keywords.

  A blank (or whitespace-only) query returns the full catalog.
  """
  def search(query) when is_binary(query) do
    case query |> String.trim() |> String.downcase() do
      "" -> @emojis
      needle -> for {haystack, emoji} <- @index, String.contains?(haystack, needle), do: emoji
    end
  end
end
```

- [ ] **Step 5: Run the Emoji tests**

```
mix test test/phoenix_chat/emoji_test.exs
```

Expected: `6 tests, 0 failures`.

- [ ] **Step 6: Write the failing `EmojiPickerComponent` test**

Create `test/phoenix_chat_web/components/emoji_picker_component_test.exs`. It defines a minimal host LiveView that mounts the component and records the bubbled `"emoji_picked"` event, then drives it with `live_isolated`. `use PhoenixChatWeb, :live_view` maps to bare `Phoenix.LiveView` (no app layout), so `live_isolated` renders the host cleanly:

```elixir
defmodule PhoenixChatWeb.EmojiPickerComponentTest do
  use PhoenixChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defmodule HostLive do
    use PhoenixChatWeb, :live_view

    @impl true
    def mount(_params, _session, socket), do: {:ok, assign(socket, :picked, nil)}

    @impl true
    def handle_event("emoji_picked", %{"emoji" => emoji, "target" => target}, socket) do
      {:noreply, assign(socket, :picked, "#{target}:#{emoji}")}
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
      |> form("#emoji-picker form", %{q: "tada"})
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
```

- [ ] **Step 7: Run to verify it fails**

```
mix test test/phoenix_chat_web/components/emoji_picker_component_test.exs
```

Expected: `3 tests, 3 failures` — every test errors because `PhoenixChatWeb.EmojiPickerComponent` is not defined (e.g. `** (UndefinedFunctionError) function PhoenixChatWeb.EmojiPickerComponent.__live__/0 is undefined (module PhoenixChatWeb.EmojiPickerComponent is not available)` from `render_component`, and the module-not-available render error from `live_isolated`).

- [ ] **Step 8: Implement `PhoenixChatWeb.EmojiPickerComponent`**

Create `lib/phoenix_chat_web/components/emoji_picker_component.ex`. Search + category tabs target `@myself`; the pick buttons carry **no** `phx-target`, so `phx-click="emoji_picked"` bubbles to the enclosing LiveView. Classes use the Glass semantic tokens already used by `core_components.ex`/`chat_live` (`bg-field-background`, `border-border`, `text-muted`, `bg-accent-soft`, `hover:bg-surface-hover`). Every user-facing string is `gettext/1`:

```elixir
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
      <form phx-change="search" phx-target={@myself} autocomplete="off">
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
```

- [ ] **Step 9: Run the component tests**

```
mix test test/phoenix_chat_web/components/emoji_picker_component_test.exs
```

Expected: `3 tests, 0 failures`.

- [ ] **Step 10: Run the full suite (stays green)**

```
mix test
```

Expected: the whole suite passes — `0 failures`.

- [ ] **Step 11: Commit**

```
git add priv/emoji/emoji.json \
        lib/phoenix_chat/emoji.ex \
        lib/phoenix_chat_web/components/emoji_picker_component.ex \
        test/phoenix_chat/emoji_test.exs \
        test/phoenix_chat_web/components/emoji_picker_component_test.exs
git commit -m "Add emoji catalog and picker component" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: ChatLive — message actions menu, inline edit, soft-delete tombstone

Expand the per-message hover toolbar to **React · Edit · Delete · Copy** (Edit/Delete author-only), add inline-edit and soft-delete flows to `ChatLive`, and render the `(edited)` marker and the `This message was deleted` tombstone. This task establishes the **canonical entry helpers** (`build_entry/3`, `apply_message_update/2`, `reinsert_entry/2`) and the `editing_id`/`edit_form` assigns that Tasks 9–12 consume, and whose entry map already carries `reply_count`/`last_reply_at`/`edited?`/`deleted?` (so Task 10's thread affordance and its live count-bump render without a `KeyError`). It does **not** add a "Reply in thread" button or an `open_thread` handler — Task 10 introduces the thread affordance and all three thread handlers together, avoiding a dangling stub and a duplicate-clause bug.

**Files:**
- Modify: `lib/phoenix_chat_web/live/chat_live.ex` (anchor by `mount/3`, `open_conversation/2`, the `apply_action(:channel)` gate branch, the `handle_event/3` group, the `handle_info/2` group, `build_entry/3`, the `## Helpers` section)
- Modify: `lib/phoenix_chat_web/live/chat_live/components.ex` (anchor by `message_entry/1`)
- Modify: `lib/phoenix_chat_web/live/chat_live.html.heex` (anchor the `<.message_entry :for={{dom_id, entry} <- @streams.messages} ...>` call inside `#message-stream`)
- Test: `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: `Chat.get_message!/1 :: %Message{user, reactions}`, `Chat.update_message/3 :: {:ok,%Message{}} | {:error,cs} | {:error,:unauthorized}`, `Chat.delete_message/2 :: {:ok,%Message{}} | {:error,:unauthorized}`, `Chat.summarize_reactions/2`, `Chat.reaction_palette/0`, `PhoenixChat.Markdown.render/1` (Task 6); `Message` fields `edited_at`/`deleted_at`/`reply_count`/`last_reply_at`; PubSub `{:message_updated, msg}` and `{:message_deleted, msg}` on `"chat:channel:#{id}"`; `AccountsFixtures.user_fixture/0` (auto-joins `#general`), `ChatFixtures.message_fixture/3`, `ConnCase.log_in_user/2`.
- Produces: assigns `editing_id :: integer | nil`, `edit_form :: Phoenix.HTML.Form.t() | nil`; **canonical helpers** `build_entry/3` (entry map now also carries `reply_count`, `last_reply_at`, `edited?`, `deleted?`), `apply_message_update/2` (rebuilds a stream entry from a `%Message{}` for `{:message_updated}`, `{:message_deleted}` **and** `{:reaction_changed}`, carrying the same fields as `build_entry/3`), `reinsert_entry/2` (re-inserts the current `entry_meta` entry for a message id), plus private `rebuild_entry/3` / `message_entry_map/4`; kept baseline names `build_entries/2`, `insert_entry/2`; `handle_event` for `"edit_message"`/`"save_edit"`/`"cancel_edit"`/`"delete_message"`; `handle_info` `{:message_updated}`/`{:message_deleted}` (and re-routes `{:reaction_changed}`); `message_entry/1` attrs `me_id`/`editing_id`/`edit_form`; DOM `button[phx-click="edit_message"]` (`.cds-edit-message`), `button[phx-click="delete_message"]` (`.cds-delete-message`, `data-confirm`), `p.cds-tombstone`, inline `(edited)`, `form#edit-message-<id>`.

---

- [ ] **Step 1: Write the failing tests.** Append a new `describe` block just before the final `defp eventually(...)` helper in `test/phoenix_chat_web/live/chat_live_test.exs`:

```elixir
  describe "message actions (edit / delete)" do
    setup :register_and_log_in_user

    test "editing a message updates the body and shows (edited) for other members", %{
      conn: conn,
      user: user
    } do
      general = Chat.get_channel_by_slug!("general")
      message = message_fixture(user, general, %{body: "originalna poruka"})

      {:ok, author_view, _html} = live(conn, ~p"/c/general")

      other = user_fixture()
      other_conn = Phoenix.ConnTest.build_conn() |> log_in_user(other)
      {:ok, watcher_view, _html} = live(other_conn, ~p"/c/general")
      assert render(watcher_view) =~ "originalna poruka"

      author_view
      |> element(~s{button[phx-click="edit_message"][phx-value-message-id="#{message.id}"]})
      |> render_click()

      author_view
      |> form(~s{#edit-message-#{message.id}}, message: %{body: "izmenjena poruka"})
      |> render_submit()

      assert render(author_view) =~ "izmenjena poruka"
      assert render(author_view) =~ "(edited)"

      assert render(watcher_view) =~ "izmenjena poruka"
      assert render(watcher_view) =~ "(edited)"
      refute render(watcher_view) =~ "originalna poruka"
    end

    test "an empty edit is rejected and keeps the message unchanged", %{conn: conn, user: user} do
      general = Chat.get_channel_by_slug!("general")
      message = message_fixture(user, general, %{body: "ostajem ista"})

      {:ok, view, _html} = live(conn, ~p"/c/general")

      view
      |> element(~s{button[phx-click="edit_message"][phx-value-message-id="#{message.id}"]})
      |> render_click()

      html =
        view
        |> form(~s{#edit-message-#{message.id}}, message: %{body: "   "})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert render(view) =~ "ostajem ista"
    end

    test "deleting a message shows a tombstone for other members", %{conn: conn, user: user} do
      general = Chat.get_channel_by_slug!("general")
      message = message_fixture(user, general, %{body: "poruka za brisanje"})

      {:ok, author_view, _html} = live(conn, ~p"/c/general")

      other = user_fixture()
      other_conn = Phoenix.ConnTest.build_conn() |> log_in_user(other)
      {:ok, watcher_view, _html} = live(other_conn, ~p"/c/general")
      assert render(watcher_view) =~ "poruka za brisanje"

      author_view
      |> element(~s{button[phx-click="delete_message"][phx-value-message-id="#{message.id}"]})
      |> render_click()

      assert has_element?(author_view, ".cds-tombstone", "This message was deleted")
      assert has_element?(watcher_view, ".cds-tombstone", "This message was deleted")
      refute render(watcher_view) =~ "poruka za brisanje"
      refute has_element?(watcher_view, ~s{button[phx-click="edit_message"]})
    end

    test "a non-author sees no edit or delete controls", %{conn: conn} do
      general = Chat.get_channel_by_slug!("general")
      author = user_fixture()
      message_fixture(author, general, %{body: "tudja poruka"})

      {:ok, view, _html} = live(conn, ~p"/c/general")

      assert render(view) =~ "tudja poruka"
      refute has_element?(view, ~s{button[phx-click="edit_message"]})
      refute has_element?(view, ~s{button[phx-click="delete_message"]})
      # everyone can still react and copy
      assert has_element?(view, ".cds-reaction-add")
    end
  end
```

- [ ] **Step 2: Run to verify it fails.**

```bash
mix test test/phoenix_chat_web/live/chat_live_test.exs
```

Expected: **3 failures** — the `edit`, `empty edit`, and `delete` tests fail with `ArgumentError` because `selector "button[phx-click=\"edit_message\"]..."` (or `delete_message`) returns no element to `render_click`. The "non-author" test already passes (its edit/delete controls don't exist yet, `.cds-reaction-add` already does). Every pre-existing test still passes.

- [ ] **Step 3: Add new assigns + event handlers in `chat_live.ex`.**

(3a) In `mount/3`, add the two edit assigns. Replace:

```elixir
       palette_for: nil,
       entry_meta: %{},
```

with:

```elixir
       palette_for: nil,
       editing_id: nil,
       edit_form: nil,
       entry_meta: %{},
```

(3b) In `open_conversation/2`, reset them on every conversation open. Replace:

```elixir
      palette_for: nil,
      entry_meta: Map.new(entries, &{&1.id, &1})
```

with:

```elixir
      palette_for: nil,
      editing_id: nil,
      edit_form: nil,
      entry_meta: Map.new(entries, &{&1.id, &1})
```

(3c) Reset them in the join-gate branch too. In the `apply_action(socket, :channel, %{"slug" => slug})` gate (`true ->`) branch, replace:

```elixir
           entry_meta: %{},
           palette_for: nil
         )
```

with:

```elixir
           entry_meta: %{},
           editing_id: nil,
           edit_form: nil,
           palette_for: nil
         )
```

(3d) Add the new `handle_event/3` clauses immediately after the `handle_event("pick_reaction", params, socket)` clause (the one ending in `{:noreply, socket}`), keeping them contiguous with the other `handle_event` clauses:

```elixir
  def handle_event("edit_message", %{"message-id" => id}, socket) do
    message = Chat.get_message!(String.to_integer(id))
    me = current_user(socket)

    if message.user_id == me.id and is_nil(message.deleted_at) do
      form = to_form(%{"body" => message.body}, as: :message)

      {:noreply,
       socket
       |> assign(editing_id: message.id, edit_form: form)
       |> reinsert_entry(message.id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    case socket.assigns.editing_id do
      nil ->
        {:noreply, socket}

      id ->
        {:noreply,
         socket
         |> assign(editing_id: nil, edit_form: nil)
         |> reinsert_entry(id)}
    end
  end

  def handle_event("save_edit", %{"message" => %{"body" => body}}, socket) do
    case socket.assigns.editing_id do
      nil ->
        {:noreply, socket}

      id ->
        message = Chat.get_message!(id)

        case Chat.update_message(current_user(socket), message, %{body: body}) do
          {:ok, _message} ->
            # The {:message_updated, msg} broadcast re-renders the entry for
            # everyone (including this client), which also drops the edit form.
            {:noreply, assign(socket, editing_id: nil, edit_form: nil)}

          {:error, %Ecto.Changeset{} = changeset} ->
            socket = assign(socket, edit_form: to_form(changeset, as: :message))
            {:noreply, reinsert_entry(socket, id)}

          {:error, :unauthorized} ->
            {:noreply,
             socket
             |> assign(editing_id: nil, edit_form: nil)
             |> reinsert_entry(id)
             |> put_flash(:error, gettext("You can only edit your own messages"))}
        end
    end
  end

  def handle_event("delete_message", %{"message-id" => id}, socket) do
    message = Chat.get_message!(String.to_integer(id))

    case Chat.delete_message(current_user(socket), message) do
      {:ok, _message} ->
        # The {:message_deleted, msg} broadcast renders the tombstone for everyone.
        {:noreply, socket}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You can only delete your own messages"))}
    end
  end
```

- [ ] **Step 4: Rebuild the entry map, add the `{:message_updated}`/`{:message_deleted}` handlers, and the canonical helpers in `chat_live.ex`.**

(4a) Replace the whole existing `handle_info({:reaction_changed, message}, socket)` clause (the ~23-line block from `def handle_info({:reaction_changed, message}, socket) do` through its closing `end`) with these three delegating clauses, placed immediately after the `handle_info({:new_message, message}, socket)` clause (do **not** re-emit `@impl true` — these follow the `@impl true`-tagged `{:new_message}` clause):

```elixir
  def handle_info({:message_updated, message}, socket) do
    {:noreply, apply_message_update(socket, message)}
  end

  def handle_info({:message_deleted, message}, socket) do
    {:noreply, apply_message_update(socket, message)}
  end

  def handle_info({:reaction_changed, message}, socket) do
    {:noreply, apply_message_update(socket, message)}
  end
```

(4b) Replace the existing `build_entry/3` function with this trio (every entry now carries `edited?`, `deleted?`, `reply_count`, `last_reply_at` via a shared `message_entry_map/4`; `rebuild_entry/3` preserves stored layout flags). Replace:

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

with:

```elixir
  defp build_entry(message, prev, me_id) do
    same_day =
      prev != nil and
        DateTime.to_date(prev.inserted_at) == DateTime.to_date(message.inserted_at)

    compact? =
      same_day and prev.user_id == message.user_id and
        DateTime.diff(message.inserted_at, prev.inserted_at) < @compact_window_seconds

    message_entry_map(message, me_id, compact?, not same_day)
  end

  defp rebuild_entry(message, meta, me_id) do
    message_entry_map(message, me_id, meta.compact?, meta.day_break?)
  end

  defp message_entry_map(message, me_id, compact?, day_break?) do
    %{
      id: message.id,
      user_id: message.user_id,
      username: message.user.username,
      body: message.body,
      inserted_at: message.inserted_at,
      compact?: compact?,
      day_break?: day_break?,
      edited?: not is_nil(message.edited_at),
      deleted?: not is_nil(message.deleted_at),
      reply_count: message.reply_count,
      last_reply_at: message.last_reply_at,
      reactions: Chat.summarize_reactions(message.reactions, me_id)
    }
  end
```

(4c) Add the two canonical helpers in the `## Helpers` section (directly under the `## Helpers` comment, before `defp rescue_join_public`). `apply_message_update/2` re-renders an entry in place when the message belongs to the active channel; `reinsert_entry/2` forces a re-render of an existing entry so it picks up the current `editing_id`/`edit_form`/`palette_for` attrs:

```elixir
  # Re-render one message entry in place (preserving its grouping flags) when the
  # message belongs to the open channel. Used by edit/delete/reaction broadcasts.
  defp apply_message_update(socket, message) do
    %{active: active, entry_meta: entry_meta} = socket.assigns

    if active && message.channel_id == active.id do
      me = current_user(socket)
      meta = Map.get(entry_meta, message.id, %{compact?: false, day_break?: false})
      insert_entry(socket, rebuild_entry(message, meta, me.id))
    else
      socket
    end
  end

  # Stream items only re-render when explicitly inserted; force a re-render of an
  # already-known entry so it reflects the current editing_id / edit_form assigns.
  defp reinsert_entry(socket, id) do
    case Map.get(socket.assigns.entry_meta, id) do
      nil -> socket
      entry -> stream_insert(socket, :messages, entry)
    end
  end
```

- [ ] **Step 5: Expand the `message_entry/1` component.** In `lib/phoenix_chat_web/live/chat_live/components.ex`, replace the entire `message_entry/1` (its `attr` declarations through the closing `end` of the function) with this version — it adds `me_id`/`editing_id`/`edit_form` attrs, keeps the Task 6 Markdown body inside a **block** `<div data-msg-body>`, renders the tombstone / inline edit form / `(edited)` marker, expands the toolbar to React · Edit · Delete · Copy (Edit/Delete gated by `@entry.user_id == @me_id`), and hides the toolbar, reactions, and palette while a message is deleted or being edited:

```elixir
  attr :id, :string, required: true
  attr :entry, :map, required: true
  attr :palette_for, :any, default: nil
  attr :me_id, :any, required: true
  attr :editing_id, :any, default: nil
  attr :edit_form, :any, default: nil

  def message_entry(assigns) do
    ~H"""
    <div id={@id}>
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
                (r.mine && "cds-reaction-chip-mine border-accent bg-accent-soft text-accent-soft-foreground") ||
                  "border-border text-muted hover:border-border-secondary"
              ]}
            >
              <span>{r.emoji}</span>
              <span class="font-medium tabular-nums">{r.count}</span>
            </button>
          </div>
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
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 6: Pass the new attrs from the template.** In `lib/phoenix_chat_web/live/chat_live.html.heex`, inside `#message-stream`, replace:

```heex
              <.message_entry
                :for={{dom_id, entry} <- @streams.messages}
                id={dom_id}
                entry={entry}
                palette_for={@palette_for}
              />
```

with:

```heex
              <.message_entry
                :for={{dom_id, entry} <- @streams.messages}
                id={dom_id}
                entry={entry}
                palette_for={@palette_for}
                me_id={@current_scope.user.id}
                editing_id={@editing_id}
                edit_form={@edit_form}
              />
```

- [ ] **Step 7: Run the new tests (PASS).**

```bash
mix test test/phoenix_chat_web/live/chat_live_test.exs
```

Expected: **0 failures**. The author's edit re-renders the Markdown body plus `(edited)` on the second connected LiveView via `{:message_updated}`; the blank edit surfaces `can't be blank` and keeps the original body; delete renders `.cds-tombstone` on both LiveViews via `{:message_deleted}`; and the non-author never sees `edit_message`/`delete_message` controls while still seeing `.cds-reaction-add`.

- [ ] **Step 8: Run the full suite (green).**

```bash
mix test
```

Expected: **0 failures** — the pre-existing reaction/grouping tests (`reactions toggle and update in real time`, `reaction updates keep message grouping intact`) still pass because `{:reaction_changed}` now routes through the shared `apply_message_update/2` + `rebuild_entry/3` path, which preserves each entry's `compact?`/`day_break?` flags.

- [ ] **Step 9: Commit.**

```bash
git add lib/phoenix_chat_web/live/chat_live.ex lib/phoenix_chat_web/live/chat_live/components.ex lib/phoenix_chat_web/live/chat_live.html.heex test/phoenix_chat_web/live/chat_live_test.exs
git commit -m "Add message actions: inline edit and soft-delete tombstone" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: ChatLive — wire the full emoji picker (reactions + composer)

Render Task 7's `PhoenixChatWeb.EmojiPickerComponent` from a **"＋"** on the reaction quick-palette **and** from the composer, and route its bubbled `"emoji_picked"` event: `target: "reaction"` toggles `Chat.toggle_reaction/3`; `target: "composer"` inserts the emoji into the message draft. One picker instance renders in a top-level overlay driven by an `emoji_picker` assign. `Chat.reaction_palette/0` stays as the quick row.

**Files:**
- Modify: `lib/phoenix_chat_web/live/chat_live.ex` (anchor `mount/3`, `open_conversation/2`, the `apply_action(:channel)` gate branch, the `handle_event/3` group)
- Modify: `lib/phoenix_chat_web/live/chat_live/components.ex` (anchor `message_entry/1`'s quick-palette block)
- Modify: `lib/phoenix_chat_web/live/chat_live.html.heex` (anchor the composer emoji affordance; add the top-level picker overlay)
- Modify: `assets/js/app.js` (anchor the `ComposerKeys` hook)
- Test: `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: `PhoenixChatWeb.EmojiPickerComponent` (Task 7 — assigns `id`/`target`/`message_id`; bubbles `"emoji_picked"` with `%{"emoji" => char, "target" => to_string(target), "message-id" => id}`), `Chat.toggle_reaction/3` (Task 5), `Chat.get_message!/1`, `Chat.reaction_palette/0`, `Chat.summarize_reactions/2`; PubSub `{:reaction_changed, msg}`; the Task 8 helpers `reinsert_entry/2` and `apply_message_update/2`; fixtures `user_fixture/0`, `message_fixture/3`.
- Produces: assign `emoji_picker :: nil | %{target: :reaction, message_id: String.t()} | %{target: :composer}`; `handle_event` for `"open_reaction_picker"`, `"open_composer_picker"`, `"close_emoji_picker"`, `"draft_change"`, and two `"emoji_picked"` clauses; DOM `button.cds-emoji-more[phx-click="open_reaction_picker"]`, `button[phx-click="open_composer_picker"]`, overlay `#emoji-picker-overlay` hosting `#emoji-picker`; a `ComposerKeys` `"set-composer-value"` handler **gated to the opted-in main composer** via `data-value-event`.

---

- [ ] **Step 1: Write the failing tests.** Append a new `describe` block just before the final `defp eventually(...)` helper in `test/phoenix_chat_web/live/chat_live_test.exs`:

```elixir
  describe "emoji picker (reactions + composer)" do
    setup :register_and_log_in_user

    test "picking an arbitrary emoji from the reaction picker adds a reaction chip", %{
      conn: conn,
      user: user
    } do
      general = Chat.get_channel_by_slug!("general")
      message = message_fixture(user, general, %{body: "reaguj emodzijem"})

      {:ok, view, _html} = live(conn, ~p"/c/general")

      # open the quick palette, then the full picker via the "+"
      view
      |> element(~s{button.cds-reaction-add[phx-value-message-id="#{message.id}"]})
      |> render_click()

      view
      |> element(~s{button.cds-emoji-more[phx-value-message-id="#{message.id}"]})
      |> render_click()

      assert has_element?(view, "#emoji-picker")

      # search for an emoji outside the quick palette and pick it
      view |> form("#emoji-picker form", %{q: "clown"}) |> render_change()
      view |> element(~s{#emoji-picker button[phx-value-emoji="🤡"]}) |> render_click()

      assert has_element?(view, ".cds-reaction-chip-mine", "🤡")
      refute has_element?(view, "#emoji-picker")
    end

    test "picking an emoji from the composer inserts it into the message draft", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      view |> form("#composer", message: %{body: "zdravo "}) |> render_change()

      view |> element(~s{button[phx-click="open_composer_picker"]}) |> render_click()
      assert has_element?(view, "#emoji-picker")

      view |> element(~s{#emoji-picker button[phx-value-emoji="😀"]}) |> render_click()

      assert has_element?(view, "#composer textarea", "zdravo 😀")
      refute has_element?(view, "#emoji-picker")
    end
  end
```

- [ ] **Step 2: Run to verify it fails.**

```bash
mix test test/phoenix_chat_web/live/chat_live_test.exs
```

Expected: **2 failures** — the reaction test fails at `element(~s{button.cds-emoji-more...})` (the "+" does not exist yet); the composer test fails at `form("#composer", ...) |> render_change()` because `#composer` has no `phx-change` handler. Pre-existing tests still pass.

- [ ] **Step 3: Add the `emoji_picker` assign to `mount/3`.** In `lib/phoenix_chat_web/live/chat_live.ex`, insert it immediately before `gate?: false,` (the 7-space-indented `mount/3` occurrence — **not** the 6-space one in `open_conversation/2`). Replace:

```elixir
       gate?: false,
```

with:

```elixir
       emoji_picker: nil,
       gate?: false,
```

- [ ] **Step 4: Reset the picker on conversation open and on the join gate.** In `open_conversation/2`, replace:

```elixir
      entry_meta: Map.new(entries, &{&1.id, &1})
```

with:

```elixir
      emoji_picker: nil,
      entry_meta: Map.new(entries, &{&1.id, &1})
```

Then in the `apply_action(socket, :channel, %{"slug" => slug})` gate (`true ->`) branch, replace:

```elixir
           palette_for: nil
         )
```

with:

```elixir
           emoji_picker: nil,
           palette_for: nil
         )
```

- [ ] **Step 5: Add the picker `handle_event/3` clauses.** In `lib/phoenix_chat_web/live/chat_live.ex`, add these clauses immediately after the `handle_event("delete_message", ...)` clause added in Task 8:

```elixir
  def handle_event("open_reaction_picker", %{"message-id" => id}, socket) do
    {:noreply,
     socket
     |> assign(emoji_picker: %{target: :reaction, message_id: id}, palette_for: nil)
     |> reinsert_entry(String.to_integer(id))}
  end

  def handle_event("open_composer_picker", _params, socket) do
    {:noreply, assign(socket, emoji_picker: %{target: :composer})}
  end

  def handle_event("close_emoji_picker", _params, socket) do
    {:noreply, assign(socket, emoji_picker: nil)}
  end

  def handle_event("draft_change", %{"message" => %{"body" => body}}, socket) do
    {:noreply, assign(socket, form: to_form(%{"body" => body}, as: :message))}
  end

  def handle_event("emoji_picked", %{"emoji" => emoji, "target" => "reaction", "message-id" => id}, socket) do
    message = Chat.get_message!(id)
    _ = Chat.toggle_reaction(current_user(socket), message, emoji)
    # The {:reaction_changed, msg} broadcast re-renders the chip via apply_message_update/2.
    {:noreply, assign(socket, emoji_picker: nil)}
  end

  def handle_event("emoji_picked", %{"emoji" => emoji, "target" => "composer"}, socket) do
    body = socket.assigns.form.params["body"] || ""
    new_body = body <> emoji

    {:noreply,
     socket
     |> assign(form: to_form(%{"body" => new_body}, as: :message), emoji_picker: nil)
     |> push_event("set-composer-value", %{value: new_body})}
  end
```

- [ ] **Step 6: Add the "＋" to the quick-palette block.** In `lib/phoenix_chat_web/live/chat_live/components.ex`, inside `message_entry/1`'s palette popover, add the "more" button immediately after the `:for` palette button (still inside the `<div :if={@palette_for == @entry.id and not @entry.deleted?} ...>`). Replace:

```heex
          <button
            :for={emoji <- PhoenixChat.Chat.reaction_palette()}
            phx-click="pick_reaction"
            phx-value-message-id={@entry.id}
            phx-value-emoji={emoji}
            class="cds-palette-item cursor-pointer rounded-lg px-1.5 py-1 text-base hover:bg-surface-hover"
          >
            {emoji}
          </button>
        </div>
```

with:

```heex
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
```

- [ ] **Step 7: Rewire the composer emoji affordance, opt the main composer into `set-composer-value`, and add the picker overlay.** In `lib/phoenix_chat_web/live/chat_live.html.heex`:

(7a) Add `phx-change="draft_change"` to the composer form. Replace:

```heex
          <.form for={@form} id="composer" phx-submit="send_message" class="mx-auto max-w-3xl">
```

with:

```heex
          <.form
            for={@form}
            id="composer"
            phx-change="draft_change"
            phx-submit="send_message"
            class="mx-auto max-w-3xl"
          >
```

(7b) Opt **only the main composer** into server-pushed value replacements, so the emoji picker can never clobber the thread reply draft (Task 10). Replace:

```heex
                placeholder={gettext("Message %{name}", name: @conversation_title)}
                phx-hook="ComposerKeys"
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
```

with:

```heex
                placeholder={gettext("Message %{name}", name: @conversation_title)}
                phx-hook="ComposerKeys"
                data-value-event="set-composer-value"
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
```

(7c) Replace the whole composer emoji block (the `<div class="relative flex items-center"> … </div>` containing `#composer-emoji-btn` and `#composer-emoji-panel`):

```heex
                <div class="relative flex items-center">
                  <.icon_button
                    type="button"
                    id="composer-emoji-btn"
                    phx-click={JS.toggle(to: "#composer-emoji-panel", display: "flex")}
                    class="size-8"
                    title={gettext("Emoji")}
                    aria-label={gettext("Emoji")}
                  >
                    <.icon name="hero-face-smile" class="size-5" />
                  </.icon_button>
                  <div
                    id="composer-emoji-panel"
                    phx-hook="EmojiPicker"
                    data-target="#composer-input"
                    data-toggle="composer-emoji-btn"
                    class="glass absolute bottom-full left-0 mb-2 hidden w-max gap-0.5 rounded-xl border border-border bg-overlay p-1 shadow-lg"
                  >
                    <button
                      :for={emoji <- PhoenixChat.Chat.reaction_palette()}
                      type="button"
                      data-emoji={emoji}
                      class="cursor-pointer rounded-lg px-1.5 py-1 text-base hover:bg-surface-hover"
                    >
                      {emoji}
                    </button>
                  </div>
                </div>
```

with:

```heex
                <.icon_button
                  type="button"
                  id="composer-emoji-btn"
                  phx-click="open_composer_picker"
                  class="size-8"
                  title={gettext("Emoji")}
                  aria-label={gettext("Emoji")}
                >
                  <.icon name="hero-face-smile" class="size-5" />
                </.icon_button>
```

(7d) Add the top-level picker overlay. After the closing `</.cds_modal>` of the browse modal (the last element in the file), append:

```heex
<div
  :if={@emoji_picker}
  id="emoji-picker-overlay"
  class="fixed inset-0 z-50 flex items-start justify-center bg-black/40 px-4 pt-24 backdrop-blur-sm"
>
  <div
    class="glass rounded-2xl border border-border bg-overlay p-3 text-overlay-foreground shadow-2xl"
    phx-click-away={JS.push("close_emoji_picker")}
  >
    <.live_component
      module={PhoenixChatWeb.EmojiPickerComponent}
      id="emoji-picker"
      target={@emoji_picker.target}
      message_id={@emoji_picker[:message_id]}
    />
  </div>
</div>
```

- [ ] **Step 8: Add the gated `set-composer-value` handler to `ComposerKeys`.** In `assets/js/app.js`, inside `ComposerKeys.mounted()`, add the handler immediately after the existing `this.handleEvent("clear-composer", ...)` block. It only registers when the textarea opts in via `data-value-event`, so a server `push_event("set-composer-value", …)` reaches **only** the main composer and never the thread textarea (which also mounts `ComposerKeys` but sets no `data-value-event`):

```javascript
      // Server-authoritative value replacement (emoji picker → composer). Only a
      // composer that opts in via data-value-event listens, so pushing a new value
      // never clobbers another ComposerKeys textarea (e.g. the thread reply draft).
      if (this.el.dataset.valueEvent) {
        this.handleEvent(this.el.dataset.valueEvent, ({value}) => {
          this.el.value = value
          this.autosize()
          this.el.focus()
        })
      }
```

- [ ] **Step 9: Run the new tests (PASS).**

```bash
mix test test/phoenix_chat_web/live/chat_live_test.exs
```

Expected: **0 failures**. The reaction test opens the palette, opens the picker via `.cds-emoji-more`, searches "clown", picks `🤡`, and the `{:reaction_changed}` broadcast renders the `.cds-reaction-chip-mine`; the composer test syncs the draft via `draft_change`, opens the composer picker, picks `😀`, and the textarea re-renders as `zdravo 😀`.

- [ ] **Step 10: Run the full suite (green).**

```bash
mix test
```

Expected: **0 failures**.

- [ ] **Step 11: Commit.**

```bash
git add lib/phoenix_chat_web/live/chat_live.ex lib/phoenix_chat_web/live/chat_live/components.ex lib/phoenix_chat_web/live/chat_live.html.heex assets/js/app.js test/phoenix_chat_web/live/chat_live_test.exs
git commit -m "Wire the full emoji picker for reactions and the composer" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: ChatLive — thread side panel

Add a right-hand thread panel (`thread_parent` assign + `:thread_messages` stream), the `open_thread`/`close_thread`/`send_thread_reply` events, and the **"N replies · last reply <time>"** affordance under any message with `reply_count > 0`. Introduce the `open_thread` handler here (Task 8 rendered no thread button and no handler, so this is additive — no dangling stub, no duplicate clause). The affordance reads `@entry.reply_count`/`@entry.last_reply_at`, which Task 8's `build_entry/3` and `apply_message_update/2` already populate. Route `{:new_message}` so replies land in an open panel, plain replies stay out of the main timeline, and the parent affordance updates live via `{:message_updated}`, reusing Task 8's `apply_message_update/2` plus a folded-in `maybe_update_thread_parent`. Include an **"Also send to channel"** checkbox.

**Files:**
- Modify: `lib/phoenix_chat_web/live/chat_live.ex` (anchor `mount/3`, `open_conversation/2`, the `apply_action(:channel)` gate branch, the `handle_event/3` group, `handle_info({:new_message,...})` and `handle_info({:message_updated,...})`, the private-helpers section)
- Modify: `lib/phoenix_chat_web/live/chat_live/components.ex` (anchor `message_entry/1`; add `thread_panel/1`)
- Modify: `lib/phoenix_chat_web/live/chat_live.html.heex` (sibling after `</section>`)
- Modify: `assets/js/app.js` (anchor the `ComposerKeys` hook clear handler)
- Test: `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: `Chat.send_message/3` (with `"parent_message_id"`/`"also_sent_to_channel"`; broadcasts `{:new_message, reply}` **and** `{:message_updated, reloaded_parent}` — Task 4), `Chat.list_thread_replies/2 :: {[%Message{user,reactions}], cursor}`, `Chat.get_message!/1 :: %Message{user,reactions}`, `Chat.mark_read/2`; Task 8 helpers `build_entry/3`, `insert_entry/2`, `apply_message_update/2`; `ChatComponents.avatar/1`, private `format_time/1`, `icon_button/1`; `Message` fields `parent_message_id`/`reply_count`/`last_reply_at`/`also_sent_to_channel`.
- Produces: `ChatComponents.thread_panel/1`; `message_entry/1` affordance `.cds-thread-affordance`/`.cds-thread-count` (`phx-click="open_thread"`); assigns `thread_parent`/`thread_form` + stream `:thread_messages`; `handle_event` `"open_thread"`/`"close_thread"`/`"send_thread_reply"`; helpers `thread_form/0`, `thread_entry/1`, `maybe_stream_thread_reply/2`, `maybe_update_thread_parent/2`; a data-`clear-event`-aware `ComposerKeys` clear handler.

---

- [ ] **Step 1: Write the failing tests.** Append a new `describe` block just before the final `defp eventually(...)` helper in `test/phoenix_chat_web/live/chat_live_test.exs`:

```elixir
  describe "thread panel" do
    setup :register_and_log_in_user

    test "opens the thread panel from the reply affordance and shows existing replies", %{
      conn: conn,
      user: user
    } do
      general = Chat.get_channel_by_slug!("general")
      parent = message_fixture(user, general, %{body: "korenska poruka"})

      {:ok, _} =
        Chat.send_message(user, general, %{"body" => "prvi odgovor", "parent_message_id" => parent.id})

      {:ok, view, _html} = live(conn, ~p"/c/general")

      refute has_element?(view, "#thread-panel")
      assert has_element?(view, ".cds-thread-affordance")
      assert has_element?(view, ".cds-thread-count", "1")

      # A plain reply must NOT leak into the main timeline.
      refute has_element?(view, "#message-stream", "prvi odgovor")

      view |> element(".cds-thread-affordance") |> render_click()

      assert has_element?(view, "#thread-panel")
      assert has_element?(view, "#thread-panel", "korenska poruka")
      assert has_element?(view, "#thread-stream", "prvi odgovor")

      view |> element("#close-thread") |> render_click()
      refute has_element?(view, "#thread-panel")
    end

    test "a reply appears in the panel and bumps the parent count on a second LV", %{
      conn: conn,
      user: user
    } do
      general = Chat.get_channel_by_slug!("general")
      parent = message_fixture(user, general, %{body: "korenska poruka"})

      {:ok, _} =
        Chat.send_message(user, general, %{"body" => "prvi odgovor", "parent_message_id" => parent.id})

      {:ok, view1, _html} = live(conn, ~p"/c/general")

      other = user_fixture()
      other_conn = Phoenix.ConnTest.build_conn() |> log_in_user(other)
      {:ok, view2, _html} = live(other_conn, ~p"/c/general")

      assert has_element?(view2, ".cds-thread-count", "1")

      view1 |> element(".cds-thread-affordance") |> render_click()
      assert has_element?(view1, "#thread-panel")

      view1
      |> form("#thread-composer", reply: %{body: "drugi odgovor"})
      |> render_submit()

      # The reply lands in the sender's thread panel...
      assert has_element?(view1, "#thread-stream", "drugi odgovor")
      # ...but never in the main timeline (not "also sent to channel")...
      refute has_element?(view1, "#message-stream", "drugi odgovor")
      # ...and the parent's reply count updates live for the other member.
      assert has_element?(view2, ".cds-thread-count", "2")
    end
  end
```

- [ ] **Step 2: Run to verify it fails.**

```bash
mix test test/phoenix_chat_web/live/chat_live_test.exs
```

Expected: **2 failures** — both new tests fail at `assert has_element?(view, ".cds-thread-affordance")` (the affordance markup does not exist yet). Pre-existing tests still pass.

- [ ] **Step 3: Add the thread affordance to `message_entry/1`.** In `lib/phoenix_chat_web/live/chat_live/components.ex`, inside `message_entry/1`, add the affordance immediately after the reactions block's closing `</div>` (still inside the `<div class="min-w-0 flex-1">` wrapper — i.e. right before that wrapper's closing `</div>`). Replace:

```heex
              <span>{r.emoji}</span>
              <span class="font-medium tabular-nums">{r.count}</span>
            </button>
          </div>
        </div>
```

with:

```heex
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
```

- [ ] **Step 4: Add the `thread_panel/1` component.** In `lib/phoenix_chat_web/live/chat_live/components.ex`, add this component just above the `defp format_time/1` / `defp format_date/1` helpers at the bottom of the module:

```elixir
  attr :parent, :map, required: true, doc: "the %Message{} the thread is rooted at"
  attr :replies, :any, required: true, doc: "the :thread_messages stream"
  attr :form, :map, required: true, doc: "the thread reply form (as: :reply)"
  attr :title, :string, required: true, doc: "the conversation title (# channel or @ dm)"

  def thread_panel(assigns) do
    ~H"""
    <aside id="thread-panel" class="flex w-96 flex-none flex-col border-l border-border">
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
        <.form for={@form} id="thread-composer" phx-submit="send_thread_reply" class="mx-auto max-w-3xl">
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
                  checked={Phoenix.HTML.Form.normalize_value("checkbox", @form[:also_sent_to_channel].value)}
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
```

- [ ] **Step 5: Add the thread stream, assigns, and helpers in `chat_live.ex`.**

(5a) In `mount/3`, insert the thread assigns before `gate?: false,` (the 7-space-indented `mount/3` occurrence). Replace:

```elixir
       gate?: false,
```

with:

```elixir
       thread_parent: nil,
       thread_form: thread_form(),
       gate?: false,
```

(5b) Add the second stream. Replace:

```elixir
     |> stream(:messages, [])}
```

with:

```elixir
     |> stream(:messages, [])
     |> stream(:thread_messages, [])}
```

(5c) Add the helpers next to the existing `empty_form/0` / `new_create_form/0` helpers:

```elixir
  defp thread_form, do: to_form(%{"body" => "", "also_sent_to_channel" => "false"}, as: :reply)

  defp thread_entry(message) do
    %{
      id: message.id,
      username: message.user.username,
      body: message.body,
      inserted_at: message.inserted_at
    }
  end

  defp maybe_stream_thread_reply(socket, %{parent_message_id: pid} = message)
       when not is_nil(pid) do
    case socket.assigns.thread_parent do
      %{id: ^pid} -> stream_insert(socket, :thread_messages, thread_entry(message))
      _ -> socket
    end
  end

  defp maybe_stream_thread_reply(socket, _message), do: socket

  defp maybe_update_thread_parent(
         %{assigns: %{thread_parent: %{id: id}}} = socket,
         %{id: id} = message
       ),
       do: assign(socket, thread_parent: message)

  defp maybe_update_thread_parent(socket, _message), do: socket
```

- [ ] **Step 6: Add the thread events.** In `lib/phoenix_chat_web/live/chat_live.ex`, add these three clauses immediately after the existing `handle_event("send_message", ...)` clause:

```elixir
  def handle_event("open_thread", %{"message-id" => id}, socket) do
    parent = Chat.get_message!(id)
    {replies, _cursor} = Chat.list_thread_replies(parent)
    entries = Enum.map(replies, &thread_entry/1)

    {:noreply,
     socket
     |> assign(thread_parent: parent, thread_form: thread_form())
     |> stream(:thread_messages, entries, reset: true)}
  end

  def handle_event("close_thread", _params, socket) do
    {:noreply,
     socket
     |> assign(thread_parent: nil, thread_form: thread_form())
     |> stream(:thread_messages, [], reset: true)}
  end

  def handle_event("send_thread_reply", %{"reply" => params}, socket) do
    %{active: channel, thread_parent: parent} = socket.assigns

    attrs = %{
      "body" => params["body"],
      "parent_message_id" => parent.id,
      "also_sent_to_channel" => params["also_sent_to_channel"]
    }

    case Chat.send_message(current_user(socket), channel, attrs) do
      {:ok, _reply} ->
        {:noreply,
         socket
         |> assign(thread_form: thread_form())
         |> push_event("clear-thread-composer", %{})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, thread_form: to_form(changeset, as: :reply))}

      {:error, :not_a_member} ->
        {:noreply, put_flash(socket, :error, gettext("You are not a member of this channel"))}
    end
  end
```

- [ ] **Step 7: Route `{:new_message}` and fold thread updates into `{:message_updated}`.** In `lib/phoenix_chat_web/live/chat_live.ex`:

Replace the entire existing `{:new_message}` clause — **the `old_string` must include the `@impl true` attribute line above it** so the replacement does not stack a second `@impl true`. Replace:

```elixir
  @impl true
  def handle_info({:new_message, message}, socket) do
    %{active: active} = socket.assigns
    me = current_user(socket)

    cond do
      active && message.channel_id == active.id ->
        Chat.mark_read(me, active)
        entry = build_entry(message, socket.assigns.newest, me.id)

        {:noreply,
         socket
         |> assign(newest: message, messages_empty?: false)
         |> insert_entry(entry)}

      message.user_id == me.id ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> update(:channels, &bump_unread(&1, message.channel_id))
         |> update(:dms, &bump_unread(&1, message.channel_id))}
    end
  end
```

with (it streams a reply into an open panel first, keeps plain replies out of the timeline and root-only unread badges, and otherwise preserves the baseline behavior):

```elixir
  @impl true
  def handle_info({:new_message, message}, socket) do
    socket = maybe_stream_thread_reply(socket, message)
    %{active: active} = socket.assigns
    me = current_user(socket)

    cond do
      # A thread reply not mirrored to the channel never touches the timeline
      # or the (root-only) unread badges — the panel handled it above.
      message.parent_message_id && !message.also_sent_to_channel ->
        {:noreply, socket}

      active && message.channel_id == active.id ->
        Chat.mark_read(me, active)
        entry = build_entry(message, socket.assigns.newest, me.id)

        {:noreply,
         socket
         |> assign(newest: message, messages_empty?: false)
         |> insert_entry(entry)}

      message.user_id == me.id ->
        {:noreply, socket}

      # An "also sent to channel" reply from another member: visible on reload
      # via list_messages, but replies never bump the root-only unread badge.
      message.parent_message_id ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> update(:channels, &bump_unread(&1, message.channel_id))
         |> update(:dms, &bump_unread(&1, message.channel_id))}
    end
  end
```

Then replace the `{:message_updated}` clause added in Task 8 (this clause has **no** `@impl true` above it — it follows the `@impl true`-tagged `{:new_message}` clause — so neither the `old_string` nor the `new_string` includes `@impl true`). Replace:

```elixir
  def handle_info({:message_updated, message}, socket) do
    {:noreply, apply_message_update(socket, message)}
  end
```

with (preserves Task 8's `apply_message_update/2` timeline re-render and adds live thread-parent sync):

```elixir
  def handle_info({:message_updated, message}, socket) do
    {:noreply,
     socket
     |> maybe_update_thread_parent(message)
     |> apply_message_update(message)}
  end
```

- [ ] **Step 8: Reset the thread on conversation open and on the join gate.** In `open_conversation/2`, replace:

```elixir
      emoji_picker: nil,
      entry_meta: Map.new(entries, &{&1.id, &1})
    )
    |> stream(:messages, entries, reset: true)
  end
```

with:

```elixir
      emoji_picker: nil,
      thread_parent: nil,
      entry_meta: Map.new(entries, &{&1.id, &1})
    )
    |> stream(:messages, entries, reset: true)
    |> stream(:thread_messages, [], reset: true)
  end
```

Then in the `apply_action(socket, :channel, %{"slug" => slug})` gate (`true ->`) branch, replace:

```elixir
           emoji_picker: nil,
           palette_for: nil
         )
         |> stream(:messages, [], reset: true)}
```

with:

```elixir
           emoji_picker: nil,
           thread_parent: nil,
           palette_for: nil
         )
         |> stream(:messages, [], reset: true)
         |> stream(:thread_messages, [], reset: true)}
```

- [ ] **Step 9: Render the panel.** In `lib/phoenix_chat_web/live/chat_live.html.heex`, add the panel as a sibling immediately after the closing `</section>` and before the top-level row's closing `</div>`. Replace:

```heex
  </section>
</div>
```

with:

```heex
  </section>

  <.thread_panel
    :if={@active && @thread_parent}
    parent={@thread_parent}
    replies={@streams.thread_messages}
    form={@thread_form}
    title={@conversation_title}
  />
</div>
```

- [ ] **Step 10: Make the composer clear event configurable.** In `assets/js/app.js`, inside `ComposerKeys.mounted()`, replace:

```javascript
      this.handleEvent("clear-composer", () => {
        this.el.value = ""
        this.autosize()
      })
```

with:

```javascript
      // Each composer clears on its own event so the thread composer and the
      // main composer never wipe each other's draft.
      const clearEvent = this.el.dataset.clearEvent || "clear-composer"
      this.handleEvent(clearEvent, () => {
        this.el.value = ""
        this.autosize()
      })
```

- [ ] **Step 11: Run the new tests (PASS).**

```bash
mix test test/phoenix_chat_web/live/chat_live_test.exs
```

Expected: **0 failures**. The affordance shows `1`; opening it renders `#thread-panel` with the parent body and the reply in `#thread-stream`; sending a reply appends it to the panel, keeps it out of `#message-stream`, and bumps `.cds-thread-count` to `2` on the second LV via `{:message_updated}`.

- [ ] **Step 12: Run the full suite (green).**

```bash
mix test
```

Expected: **0 failures**.

- [ ] **Step 13: Commit.**

```bash
git add lib/phoenix_chat_web/live/chat_live.ex lib/phoenix_chat_web/live/chat_live/components.ex lib/phoenix_chat_web/live/chat_live.html.heex assets/js/app.js test/phoenix_chat_web/live/chat_live_test.exs
git commit -m "Add thread side panel to ChatLive" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: Typing indicators

Ephemeral, no-schema typing signals. `ComposerKeys` pushes a throttled `"typing"` event on input; `ChatLive` rebroadcasts via `Chat.broadcast_typing/2`; every connected member except the author shows "X is typing…" beneath the message list, auto-cleared after a 4s TTL and cleared immediately when that user's message arrives. Additive to Task 10's `mount/3` and `{:new_message}` routing.

**Files:**
- Modify: `lib/phoenix_chat/chat.ex` (add `broadcast_typing/2` after `summarize_reactions/2`)
- Modify: `lib/phoenix_chat_web/live/chat_live/components.ex` (add `typing_indicator/1` + `typing_text/1` after `conversation_intro/1`)
- Modify: `lib/phoenix_chat_web/live/chat_live.ex` (`@typing_ttl`, `typing_users` assign, `handle_event("typing", ...)`, `handle_info({:typing,...})`/`({:clear_typing,...})`, clear author in the `{:new_message}` active-channel branch)
- Modify: `lib/phoenix_chat_web/live/chat_live.html.heex` (render `<.typing_indicator>` between the message list and the composer)
- Modify: `assets/js/app.js` (`ComposerKeys` pushes a throttled `"typing"` event)
- Test: `test/phoenix_chat/chat_test.exs`, `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: private `broadcast!/2` (topic `"chat:channel:#{id}"`); the Task 10 `{:new_message}` clause; `current_user/1`; fixtures `user_fixture/0`, `channel_fixture/1`, `register_and_log_in_user`, `log_in_user/2`.
- Produces: `Chat.broadcast_typing(%User{}, %Channel{}) :: :ok` broadcasting `{:typing, %{user_id, username}}`; assign `typing_users :: %{user_id => username}`; `handle_event("typing", ...)`; `handle_info({:typing, ...})`/`({:clear_typing, ...})`; `ChatComponents.typing_indicator/1` (`.cds-typing`); throttled `"typing"` push from `ComposerKeys`.

---

- [ ] **Step 1: Write the failing context test.** Append this `describe` block inside `PhoenixChat.ChatTest` in `test/phoenix_chat/chat_test.exs` (before its closing `end`):

```elixir
  describe "broadcast_typing/2" do
    test "broadcasts an ephemeral typing signal to subscribers and returns :ok" do
      creator = user_fixture()
      channel = channel_fixture(creator)
      :ok = Chat.subscribe(channel)

      assert :ok = Chat.broadcast_typing(creator, channel)

      assert_receive {:typing, %{user_id: user_id, username: username}}
      assert user_id == creator.id
      assert username == creator.username
    end

    test "does not persist anything" do
      creator = user_fixture()
      channel = channel_fixture(creator)

      before = Chat.list_messages(channel)
      assert :ok = Chat.broadcast_typing(creator, channel)
      assert Chat.list_messages(channel) == before
    end
  end
```

- [ ] **Step 2: Run to verify it fails.**

```bash
mix test test/phoenix_chat/chat_test.exs
```

Expected: **2 failures** — `** (UndefinedFunctionError) function PhoenixChat.Chat.broadcast_typing/2 is undefined or private`. Pre-existing tests still pass.

- [ ] **Step 3: Implement `Chat.broadcast_typing/2`.** In `lib/phoenix_chat/chat.ex`, add a `## Typing` section at the end of the module (after `summarize_reactions/2`, before the module's closing `end`):

```elixir
  ## Typing

  @doc """
  Broadcasts an ephemeral typing signal on the channel topic. Nothing is
  persisted; receivers show it for a few seconds and let it expire on a TTL.
  """
  def broadcast_typing(%User{} = user, %Channel{} = channel) do
    broadcast!(channel, {:typing, %{user_id: user.id, username: user.username}})
    :ok
  end
```

- [ ] **Step 4: Run the context test (PASS).**

```bash
mix test test/phoenix_chat/chat_test.exs
```

Expected: **0 failures**.

- [ ] **Step 5: Write the failing LiveView tests.** Add these two tests inside the existing `describe "channel view"` block (which already has `setup :register_and_log_in_user`) in `test/phoenix_chat_web/live/chat_live_test.exs`, right before that block's closing `end`:

```elixir
    test "shows a typing indicator to other members and never to the typist", %{conn: conn} do
      other = user_fixture()
      general = Chat.get_channel_by_slug!("general")
      {:ok, _} = Chat.join_channel(other, general)

      {:ok, view, _html} = live(conn, ~p"/c/general")

      other_conn = Phoenix.ConnTest.build_conn() |> log_in_user(other)
      {:ok, other_view, _html} = live(other_conn, ~p"/c/general")

      refute has_element?(view, ".cds-typing")

      render_hook(other_view, "typing", %{})

      assert has_element?(view, ".cds-typing", "is typing")
      assert render(view) =~ "#{other.username} is typing"
      refute has_element?(other_view, ".cds-typing")
    end

    test "a member's typing indicator clears when their message arrives", %{conn: conn} do
      other = user_fixture()
      general = Chat.get_channel_by_slug!("general")
      {:ok, _} = Chat.join_channel(other, general)

      {:ok, view, _html} = live(conn, ~p"/c/general")

      :ok = Chat.broadcast_typing(other, general)
      assert has_element?(view, ".cds-typing", "is typing")

      {:ok, _} = Chat.send_message(other, general, %{body: "gotovo"})
      refute has_element?(view, ".cds-typing")
      assert render(view) =~ "gotovo"
    end
```

- [ ] **Step 6: Run to verify it fails.**

```bash
mix test test/phoenix_chat_web/live/chat_live_test.exs
```

Expected: **2 failures** — the first crashes on `render_hook(other_view, "typing", %{})` with `FunctionClauseError` (no `handle_event("typing", ...)`); the second fails its `.cds-typing` assertion.

- [ ] **Step 7: Add the `typing_indicator/1` component.** In `lib/phoenix_chat_web/live/chat_live/components.ex`, add the component and its text helper immediately after `conversation_intro/1` (before `defp online?/2`):

```elixir
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
```

- [ ] **Step 8: Wire `ChatLive`.** In `lib/phoenix_chat_web/live/chat_live.ex`:

(8a) Add the TTL attribute right after `@compact_window_seconds`:

```elixir
  # A typing indicator auto-clears this many milliseconds after the last signal.
  @typing_ttl 4000
```

(8b) Add the assign to `mount/3`, before `gate?: false,` (the 7-space-indented `mount/3` occurrence). Replace:

```elixir
       gate?: false,
```

with:

```elixir
       typing_users: %{},
       gate?: false,
```

(8c) Add the `"typing"` event handler immediately after the existing `handle_event("send_message", ...)` clause:

```elixir
  def handle_event("typing", _params, socket) do
    if channel = socket.assigns.active do
      Chat.broadcast_typing(current_user(socket), channel)
    end

    {:noreply, socket}
  end
```

(8d) Clear the author from `typing_users` when their message arrives. In the Task 10 `handle_info({:new_message, message}, socket)` clause, in the active-channel branch, replace:

```elixir
        {:noreply,
         socket
         |> assign(newest: message, messages_empty?: false)
         |> insert_entry(entry)}
```

with:

```elixir
        {:noreply,
         socket
         |> assign(newest: message, messages_empty?: false)
         |> update(:typing_users, &Map.delete(&1, message.user_id))
         |> insert_entry(entry)}
```

(8e) Add the two typing `handle_info` clauses immediately after the `handle_info({:reaction_changed, message}, socket)` clause (before the `presence_diff` clause):

```elixir
  def handle_info({:typing, %{user_id: user_id, username: username}}, socket) do
    me = current_user(socket)

    if user_id == me.id do
      {:noreply, socket}
    else
      Process.send_after(self(), {:clear_typing, user_id}, @typing_ttl)
      {:noreply, update(socket, :typing_users, &Map.put(&1, user_id, username))}
    end
  end

  def handle_info({:clear_typing, user_id}, socket) do
    {:noreply, update(socket, :typing_users, &Map.delete(&1, user_id))}
  end
```

- [ ] **Step 9: Render the indicator.** In `lib/phoenix_chat_web/live/chat_live.html.heex`, insert `<.typing_indicator>` between the message list and the composer. Replace:

```heex
        </div>

        <div class="flex-none px-4 pb-4 pt-2">
          <.form
            for={@form}
            id="composer"
            phx-change="draft_change"
            phx-submit="send_message"
            class="mx-auto max-w-3xl"
          >
```

with:

```heex
        </div>

        <.typing_indicator users={Map.values(@typing_users)} />

        <div class="flex-none px-4 pb-4 pt-2">
          <.form
            for={@form}
            id="composer"
            phx-change="draft_change"
            phx-submit="send_message"
            class="mx-auto max-w-3xl"
          >
```

- [ ] **Step 10: Push a throttled `"typing"` event.** In `assets/js/app.js`, inside `ComposerKeys.mounted()`, add the typing listener immediately after `this.el.addEventListener("input", this.autosize)`:

```javascript
      // Tell the server the user is typing, throttled to at most once per 2s.
      this.lastTyping = 0
      this.el.addEventListener("input", () => {
        if (!this.el.value.trim()) return
        const now = Date.now()
        if (now - this.lastTyping < 2000) return
        this.lastTyping = now
        this.pushEvent("typing", {})
      })
```

- [ ] **Step 11: Run the LiveView tests (PASS).**

```bash
mix test test/phoenix_chat_web/live/chat_live_test.exs
```

Expected: **0 failures** — the second LV shows `.cds-typing` with "is typing" when the first pushes `"typing"`; the typist never sees it; and the indicator clears when that member's message arrives.

- [ ] **Step 12: Run the full suite (green).**

```bash
mix test
```

Expected: **0 failures**.

- [ ] **Step 13: Commit.**

```bash
git add lib/phoenix_chat/chat.ex lib/phoenix_chat_web/live/chat_live/components.ex lib/phoenix_chat_web/live/chat_live.ex lib/phoenix_chat_web/live/chat_live.html.heex assets/js/app.js test/phoenix_chat/chat_test.exs test/phoenix_chat_web/live/chat_live_test.exs
git commit -m "Add typing indicators" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 12: Unread divider + jump / mark-all-read

Capture the membership's `last_read_at` **before** `mark_read` into `unread_boundary_at`/`unread_boundary_id`; render a "New" divider above the first unread message; add "Jump to unread" and "Mark all as read". Additive to `open_conversation/2` (which is consolidated here) and to `message_entry/1` (add only the `:unread_boundary_id` attr and the divider block).

**Files:**
- Modify: `lib/phoenix_chat/chat.ex` (add `last_read_at/2` before `mark_read/2`)
- Modify: `lib/phoenix_chat_web/live/chat_live.ex` (`mount/3`, gate branch, `open_conversation/2`, `first_unread_id/3`, `handle_event("mark_all_read", ...)`)
- Modify: `lib/phoenix_chat_web/live/chat_live/components.ex` (`message_entry/1`)
- Modify: `lib/phoenix_chat_web/live/chat_live.html.heex` (unread bar + pass `unread_boundary_id`)
- Modify: `assets/js/app.js` (`JumpToUnread` hook)
- Test: `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: `Chat.mark_read/2`, `Chat.list_messages/2`; `open_conversation/2`, `build_entries/2`, assign `entry_meta`; `ChannelMembership.last_read_at`.
- Produces: `Chat.last_read_at(%User{}, %Channel{}) :: DateTime.t() | nil`; event `"mark_all_read"`; assigns `unread_boundary_at :: DateTime.t() | nil` and `unread_boundary_id :: integer | nil`; `first_unread_id/3`; `message_entry/1` attr `:unread_boundary_id` + `#unread-divider`; DOM `#unread-bar`, `#jump-to-unread`; JS hook `JumpToUnread`.

---

- [ ] **Step 1: Write the failing test.** Add this test inside the existing `describe "channel view"` block in `test/phoenix_chat_web/live/chat_live_test.exs`, right before that block's closing `end`:

```elixir
    test "shows the unread divider above the first unread and clears it on mark-all-read",
         %{conn: conn} do
      general = Chat.get_channel_by_slug!("general")
      other = user_fixture()
      {:ok, unread} = Chat.send_message(other, general, %{body: "novo za tebe"})

      {:ok, view, _html} = live(conn, ~p"/c/general")

      # A "New" divider is rendered inside the first unread message's stream entry.
      assert has_element?(view, "#unread-divider")
      assert has_element?(view, ~s{#messages-#{unread.id} #unread-divider})

      # Marking all read removes the divider for the reader.
      view |> element(~s{button[phx-click="mark_all_read"]}) |> render_click()

      refute has_element?(view, "#unread-divider")
    end
```

- [ ] **Step 2: Run to verify it fails.**

```bash
mix test test/phoenix_chat_web/live/chat_live_test.exs
```

Expected: the new test fails at `assert has_element?(view, "#unread-divider")` (`Expected true, got false`). All other channel-view tests still pass.

- [ ] **Step 3: Add `Chat.last_read_at/2`.** In `lib/phoenix_chat/chat.ex`, in the `## Unread` section, insert it immediately before `mark_read/2`:

```elixir
  @doc """
  Returns the membership's `last_read_at` for `user` in `channel`, or `nil`
  when there is no membership. Read this before `mark_read/2` so the caller
  can place the unread divider at the reader's last-seen position.
  """
  def last_read_at(%User{} = user, %Channel{} = channel) do
    Repo.one(
      from m in ChannelMembership,
        where: m.user_id == ^user.id and m.channel_id == ^channel.id,
        select: m.last_read_at
    )
  end
```

- [ ] **Step 4: Consolidate `open_conversation/2` to capture the boundary.** In `lib/phoenix_chat_web/live/chat_live.ex`, replace the entire `defp open_conversation(socket, channel) do … end`. **This replaces the version from Task 10, preserving the `editing_id`/`edit_form` resets (Task 8), the `emoji_picker` reset (Task 9), the `thread_parent` reset + `:thread_messages` stream reset (Task 10)**, and adding the unread-boundary capture (read `last_read_at` before `mark_read`):

```elixir
  defp open_conversation(socket, channel) do
    user = current_user(socket)
    title = conversation_title(channel, user)
    other = if channel.kind == :dm, do: Chat.dm_other_user(channel, user)
    boundary = Chat.last_read_at(user, channel)
    Chat.mark_read(user, channel)
    {messages, older_cursor} = Chat.list_messages(channel)
    entries = build_entries(messages, user.id)

    socket
    |> assign(
      active: channel,
      active_other: other,
      gate?: false,
      conversation_title: title,
      older_cursor: older_cursor,
      newest: List.last(messages),
      oldest: List.first(messages),
      messages_empty?: messages == [],
      channels: clear_unread(socket.assigns.channels, channel.id),
      dms: clear_unread(socket.assigns.dms, channel.id),
      page_title: title,
      show_dm_modal: false,
      form: empty_form(),
      palette_for: nil,
      editing_id: nil,
      edit_form: nil,
      emoji_picker: nil,
      thread_parent: nil,
      unread_boundary_at: boundary,
      unread_boundary_id: first_unread_id(messages, boundary, user.id),
      entry_meta: Map.new(entries, &{&1.id, &1})
    )
    |> stream(:messages, entries, reset: true)
    |> stream(:thread_messages, [], reset: true)
  end
```

- [ ] **Step 5: Add `first_unread_id/3`.** In `lib/phoenix_chat_web/live/chat_live.ex`, insert these clauses immediately before `defp build_entries(messages, me_id) do`:

```elixir
  # The id of the first loaded message newer than the read boundary and not
  # authored by the reader — where the "New" divider is drawn. nil = all read.
  defp first_unread_id(_messages, nil, _me_id), do: nil

  defp first_unread_id(messages, boundary, me_id) do
    Enum.find_value(messages, fn message ->
      if message.user_id != me_id and
           DateTime.compare(message.inserted_at, boundary) == :gt,
         do: message.id
    end)
  end
```

- [ ] **Step 6: Initialize the assigns in `mount/3` and the gate branch.** In `mount/3`, insert both assigns before `gate?: false,` (the 7-space-indented `mount/3` occurrence). Replace:

```elixir
       gate?: false,
```

with:

```elixir
       unread_boundary_at: nil,
       unread_boundary_id: nil,
       gate?: false,
```

Then in the `apply_action(socket, :channel, %{"slug" => slug})` gate (`true ->`) branch, replace:

```elixir
           thread_parent: nil,
           palette_for: nil
         )
```

with:

```elixir
           thread_parent: nil,
           unread_boundary_at: nil,
           unread_boundary_id: nil,
           palette_for: nil
         )
```

- [ ] **Step 7: Add the `mark_all_read` handler.** In `lib/phoenix_chat_web/live/chat_live.ex`, insert this handler immediately before `def handle_event("open_dm_modal", _params, socket) do`:

```elixir
  def handle_event("mark_all_read", _params, socket) do
    %{active: active, unread_boundary_id: id} = socket.assigns
    if active, do: Chat.mark_read(current_user(socket), active)

    socket = assign(socket, unread_boundary_at: nil, unread_boundary_id: nil)

    # The divider lives inside the boundary message's stream entry; re-insert
    # it so it re-renders without the divider now that the boundary is cleared.
    socket =
      case id && Map.get(socket.assigns.entry_meta, id) do
        nil -> socket
        entry -> stream_insert(socket, :messages, entry)
      end

    {:noreply, socket}
  end
```

- [ ] **Step 8: Add the divider to `message_entry/1`.** In `lib/phoenix_chat_web/live/chat_live/components.ex`, add the attr and the divider block only. First add the attr after the existing `edit_form` attr:

```elixir
  attr :unread_boundary_id, :any, default: nil
```

Then render the divider as the first child of the component's root. Replace:

```heex
  def message_entry(assigns) do
    ~H"""
    <div id={@id}>
      <div :if={@entry.day_break?} class="cds-day-divider flex items-center gap-3 px-2 py-2">
```

with:

```heex
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
```

- [ ] **Step 9: Wire the template.** In `lib/phoenix_chat_web/live/chat_live.html.heex`:

(9a) Add the sticky unread bar as the first child of `#message-list`. Replace:

```heex
        <div id="message-list" class="flex-1 overflow-y-auto px-2 py-4" phx-hook="ScrollToBottom">
          <div class="mx-auto max-w-3xl">
```

with:

```heex
        <div id="message-list" class="flex-1 overflow-y-auto px-2 py-4" phx-hook="ScrollToBottom">
          <div
            :if={@unread_boundary_id}
            id="unread-bar"
            class="sticky top-0 z-10 mx-auto mb-2 flex max-w-3xl items-center justify-between gap-3 rounded-lg border border-border bg-overlay px-3 py-1.5 text-sm text-overlay-foreground shadow-sm"
          >
            <button
              id="jump-to-unread"
              type="button"
              phx-hook="JumpToUnread"
              class="cursor-pointer font-medium text-danger hover:underline"
            >
              {gettext("Jump to unread")}
            </button>
            <button
              type="button"
              phx-click="mark_all_read"
              class="cursor-pointer text-muted hover:text-foreground"
            >
              {gettext("Mark all as read")}
            </button>
          </div>
          <div class="mx-auto max-w-3xl">
```

(9b) Pass the boundary id into each `message_entry`. Replace:

```heex
              <.message_entry
                :for={{dom_id, entry} <- @streams.messages}
                id={dom_id}
                entry={entry}
                palette_for={@palette_for}
                me_id={@current_scope.user.id}
                editing_id={@editing_id}
                edit_form={@edit_form}
              />
```

with:

```heex
              <.message_entry
                :for={{dom_id, entry} <- @streams.messages}
                id={dom_id}
                entry={entry}
                palette_for={@palette_for}
                me_id={@current_scope.user.id}
                editing_id={@editing_id}
                edit_form={@edit_form}
                unread_boundary_id={@unread_boundary_id}
              />
```

- [ ] **Step 10: Add the `JumpToUnread` hook.** In `assets/js/app.js`, add the hook inside the `Hooks` object, immediately after the `ScrollToBottom` block (before `ComposerKeys:`):

```javascript
  JumpToUnread: {
    mounted() {
      this.onClick = () => {
        const divider = document.getElementById("unread-divider")
        if (divider) divider.scrollIntoView({behavior: "smooth", block: "center"})
      }
      this.el.addEventListener("click", this.onClick)
    },
    destroyed() {
      this.el.removeEventListener("click", this.onClick)
    }
  },
```

- [ ] **Step 11: Run tests.**

```bash
mix test test/phoenix_chat_web/live/chat_live_test.exs
```

Expected: **0 failures** — `#unread-divider` renders inside `#messages-<id>` for the first unread, and "Mark all as read" clears it. Then run the full suite:

```bash
mix test
```

Expected: **0 failures**.

- [ ] **Step 12: Commit.**

```bash
git add lib/phoenix_chat/chat.ex lib/phoenix_chat_web/live/chat_live.ex lib/phoenix_chat_web/live/chat_live/components.ex lib/phoenix_chat_web/live/chat_live.html.heex assets/js/app.js test/phoenix_chat_web/live/chat_live_test.exs
git commit -m "Add unread divider with jump and mark-all-read" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13: Gettext sweep + final precommit

Re-extract every source string into `priv/gettext/default.pot`, merge into the locale `.po` files, add Serbian (`sr`) translations for the **exact** msgids emitted by Tasks 6–12, lock it with a completeness test, and end on a green `mix precommit`. The default locale is `sr`, so untranslated strings visibly break the app for the default user; `en` keeps empty `msgstr`s (English is the source msgid), so only `sr` is asserted complete.

**Files:**
- Create: `test/phoenix_chat_web/gettext_translations_test.exs`
- Modify: `priv/gettext/default.pot` (regenerated by `mix gettext.extract`)
- Modify: `priv/gettext/sr/LC_MESSAGES/default.po` (merge + fill Serbian `msgstr`s)
- Modify: `priv/gettext/en/LC_MESSAGES/default.po` (merged; `msgstr`s stay empty)

**Interfaces:**
- Consumes: `gettext/2`/`ngettext/4` calls from Tasks 6–12; `Expo.PO.parse_file!/1`; `Expo.Message.has_flag?/2`; the `mix precommit` alias.
- Produces: `PhoenixChatWeb.GettextTranslationsTest`; a fully-translated `sr` catalog; green `mix precommit`.

---

- [ ] **Step 1: Re-extract and merge all source strings.**

```bash
mix gettext.extract --merge
```

Expected output:

```
Extracting translations...
Extracted priv/gettext/default.pot
Wrote priv/gettext/en/LC_MESSAGES/default.po
Wrote priv/gettext/sr/LC_MESSAGES/default.po
```

Sanity-check that new, still-empty Serbian entries now exist:

```bash
grep -n -A2 'This message was deleted\|is typing\|Mark all as read\|Reply in thread\|last reply' priv/gettext/sr/LC_MESSAGES/default.po
```

You should see `msgstr ""` (or empty `msgstr[…]`) under those msgids — proof there is work to translate.

- [ ] **Step 2: Write the failing completeness test.** Create `test/phoenix_chat_web/gettext_translations_test.exs`:

```elixir
defmodule PhoenixChatWeb.GettextTranslationsTest do
  use ExUnit.Case, async: true

  alias Expo.Message.{Plural, Singular}

  @po_path "priv/gettext/sr/LC_MESSAGES/default.po"

  test "every Serbian message in default.po has a non-empty, non-fuzzy translation" do
    untranslated =
      @po_path
      |> Expo.PO.parse_file!()
      |> Map.fetch!(:messages)
      |> Enum.reject(&header?/1)
      |> Enum.filter(fn message -> fuzzy?(message) or untranslated?(message) end)
      |> Enum.map(&msgid/1)

    assert untranslated == [],
           "#{@po_path} has untranslated or fuzzy strings:\n  " <>
             Enum.join(untranslated, "\n  ")
  end

  defp header?(message), do: msgid(message) == ""

  defp fuzzy?(message), do: Expo.Message.has_flag?(message, "fuzzy")

  defp untranslated?(%Singular{msgstr: msgstr}), do: blank?(msgstr)

  defp untranslated?(%Plural{msgstr: msgstr}) do
    msgstr == %{} or Enum.any?(msgstr, fn {_index, strings} -> blank?(strings) end)
  end

  defp blank?(strings), do: strings |> IO.iodata_to_binary() |> String.trim() == ""

  defp msgid(%{msgid: msgid}), do: IO.iodata_to_binary(msgid)
end
```

- [ ] **Step 3: Run the test and confirm it FAILS.**

```bash
mix test test/phoenix_chat_web/gettext_translations_test.exs
```

Expected: **1 test, 1 failure** — the assertion lists the still-untranslated msgids extracted in Step 1 (the tombstone / edited / thread / typing / unread / emoji-picker strings).

- [ ] **Step 4: Fill in the Serbian translations.** Edit `priv/gettext/sr/LC_MESSAGES/default.po`. For every entry the merge left with an empty `msgstr`, set the Serbian translation below (informal "ti" register; copy each msgid's punctuation — the ellipsis `…` — verbatim). Leave the auto-generated `#:` reference comments and `#, elixir-autogen, elixir-format` flags untouched; any msgid already translated in a prior task keeps its existing `msgstr`. Serbian plural forms use `msgstr[0]` for n≡1, `msgstr[1]` for n≡2–4, `msgstr[2]` otherwise. These are the exact msgids emitted by Tasks 6–12:

Message actions, states, and flashes (Task 8):

```po
msgid "This message was deleted"
msgstr "Ova poruka je obrisana"

msgid "(edited)"
msgstr "(izmenjeno)"

msgid "Save"
msgstr "Sačuvaj"

msgid "Cancel"
msgstr "Otkaži"

msgid "Edit message"
msgstr "Izmeni poruku"

msgid "Delete message"
msgstr "Obriši poruku"

msgid "Delete this message?"
msgstr "Obrisati ovu poruku?"

msgid "You can only edit your own messages"
msgstr "Možeš da menjaš samo svoje poruke"

msgid "You can only delete your own messages"
msgstr "Možeš da brišeš samo svoje poruke"
```

Emoji picker (Tasks 7 and 9):

```po
msgid "More emoji"
msgstr "Više emodžija"

msgid "Search emoji"
msgstr "Pretraži emodžije"

msgid "Emoji categories"
msgstr "Kategorije emodžija"

msgid "No emoji found"
msgstr "Nema pronađenih emodžija"
```

Thread panel + "N replies" affordance (Task 10):

```po
msgid "Thread"
msgstr "Nit"

msgid "Close thread"
msgstr "Zatvori nit"

msgid "Reply in thread"
msgstr "Odgovori u niti"

msgid "Reply…"
msgstr "Odgovori…"

msgid "Also send to channel"
msgstr "Pošalji i u kanal"

msgid "Send reply"
msgstr "Pošalji odgovor"

msgid "· last reply %{time}"
msgstr "· poslednji odgovor %{time}"

msgid "reply"
msgid_plural "replies"
msgstr[0] "odgovor"
msgstr[1] "odgovora"
msgstr[2] "odgovora"

msgid "%{count} reply"
msgid_plural "%{count} replies"
msgstr[0] "%{count} odgovor"
msgstr[1] "%{count} odgovora"
msgstr[2] "%{count} odgovora"
```

Typing indicators (Task 11):

```po
msgid "%{user} is typing…"
msgstr "%{user} kuca…"

msgid "%{first} and %{second} are typing…"
msgstr "%{first} i %{second} kucaju…"

msgid "Several people are typing…"
msgstr "Više ljudi kuca…"
```

Unread divider (Task 12):

```po
msgid "New"
msgstr "Novo"

msgid "Jump to unread"
msgstr "Skoči na nepročitano"

msgid "Mark all as read"
msgstr "Označi sve kao pročitano"
```

After editing, confirm no real empty `msgstr` remains (only the header may be empty):

```bash
grep -c 'msgstr ""' priv/gettext/sr/LC_MESSAGES/default.po
```

Expected: `1` (the header `msgid ""`/`msgstr ""` only). If it is higher, fill the remaining entries.

- [ ] **Step 5: Run the completeness test and confirm it PASSES.**

```bash
mix test test/phoenix_chat_web/gettext_translations_test.exs
```

Expected:

```
.
Finished in 0.0X seconds
1 test, 0 failures
```

- [ ] **Step 6: Run the final precommit gate.** `precommit` runs `compile --warning-as-errors`, `deps.unlock --unused`, `format`, then the full `test` suite.

```bash
mix precommit
```

Expected: clean compile with no warnings, `mix format` reports nothing to change, and the suite ends with `0 failures`:

```
...
Finished in X.X seconds
NNN tests, 0 failures
```

If `mix format` rewrites the new test file, re-run `mix precommit` so the tree is clean before committing.

- [ ] **Step 7: Commit.**

```bash
git add test/phoenix_chat_web/gettext_translations_test.exs priv/gettext/default.pot priv/gettext/sr/LC_MESSAGES/default.po priv/gettext/en/LC_MESSAGES/default.po
git commit -m "Translate new Phase 1 UI strings to Serbian" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
