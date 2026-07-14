# Slack Clone — Phase 0 (Foundation) + Phase 1 (Messaging Depth) Design Spec

**Date:** 2026-07-14
**Status:** Approved by user (brainstorming session)
**Codebase:** phoenix_chat (Phoenix 1.8, LiveView 1.2, Ecto/Postgres, Tailwind v4)
**Predecessor:** `docs/superpowers/specs/2026-07-13-slack-clone-mvp-design.md` (the MVP, now built)

## 0. Context & roadmap

The MVP Slack clone is built and committed (auth + usernames, public channels, DMs,
persistent messages with cursor pagination, fixed-palette emoji reactions, unread badges,
workspace presence, per-channel WebRTC huddles, Serbian i18n). The user wants a **complete
Slack clone**, built **phase by phase**, each phase getting its own spec → plan → build.

The agreed destination roadmap:

- **Phase 0 — Foundation & theme landing** *(this spec)* — finish and commit the in-progress
  "Glass" re-theme, get a green build, and introduce the multi-workspace schema seam.
- **Phase 1 — Messaging depth** *(this spec)* — threads, message edit/delete, markdown
  rendering, full emoji picker, typing indicators, unread divider.
- **Phase 2 — Files, search & mentions** *(future spec)* — uploads/attachments, full-text
  search, @mentions + notifications/activity inbox.
- **Phase 3 — Org & admin** *(future spec)* — private channels, roles/permissions, channel &
  member management, richer user profiles & status; activates the workspace seam into real
  multi-tenancy.

This document specifies **Phase 0 and Phase 1 only**. Later phases are named for context and
to justify forward-compatible decisions, not designed here.

### Overall approach

**Extend in place.** The current architecture is clean and well-tested — a single `ChatLive`
shell, a `Chat` context enforcing membership authorization at its boundary, DMs modeled as
`channels` rows with `kind: :dm`, LiveView streams + one PubSub topic per channel. Each new
feature is added as schema columns/tables + context functions + UI, reusing the existing
machinery rather than rearchitecting. `ChatLive`/its components are split only as files grow.

## 1. Decisions log

| Question | Decision |
|---|---|
| Overall scope | Complete Slack clone, delivered in sequential phases; design one phase at a time |
| First work | Phase 0 (land Glass theme + green build + workspace seam), then Phase 1 (messaging depth) |
| Threads | Slack-style: self-ref `parent_message_id`, denormalized `reply_count`/`last_reply_at`, right-hand thread panel, "N replies" affordance in the main timeline, optional "also send to channel" |
| Multi-workspace | Bake the schema seam now (Phase 0): `workspaces` table + `channels.workspace_id`, one default workspace; no switcher UI until Phase 3 |
| Delete semantics | Soft delete (tombstone "This message was deleted"); no hard delete |
| Edit | `edited_at` marker, author-only, inline edit composer, renders "(edited)" |
| Reactions | Relax from the fixed 8-emoji palette to **any** emoji (matches Slack); keep the quick-palette row as fast access |
| Markdown | Server-side render via **MDEx** (comrak + ammonia sanitizer), Slack-lite subset; composer stays plain text |
| Emoji picker | Vendored emoji JSON dataset + a LiveComponent with server-side search (assets are npm-free) |
| Typing indicators | Ephemeral PubSub event, no schema; client debounce, server-side TTL auto-clear |
| Unread | Channel badges count root messages only (`parent_message_id IS NULL`); thread-reply unread deferred to the Phase 2 activity inbox |
| Design system | Finish the "Glass" glassmorphism theme (Inter font, light + dark, ThemeToggle); retire the dead IBM Plex / daisyUI / Carbon residue |

---

## Phase 0 — Foundation & theme landing

### 0.1 Land the Glass theme

The working tree already contains a coherent, mostly-complete re-theme (Glass tokens and
vendored Inter `@font-face` in `assets/css/app.css`; restyled `core_components.ex`,
`layouts.ex`, `root.html.heex`, `chat_live` templates, `room_live.html.heex`, and all four
`user_live` auth pages). Phase 0 **finishes and commits** it:

- **Track fonts.** `git add` the 6 untracked Inter `.woff2` files (latin + latin-ext, weights
  400/500/600). Without this the theme breaks in a fresh checkout / prod build.
- **Delete dead assets.** Remove the orphaned IBM Plex Sans `.woff2` set (referenced by no
  `@font-face`), and `assets/vendor/daisyui.js` + `assets/vendor/daisyui-theme.js` (vendored
  but never loaded — `app.css` only `@plugin`s heroicons).
- **Fix stale docs.** `core_components.ex`'s moduledoc still claims daisyUI is "the foundation
  for styling"; update it to describe the Glass semantic-token system. Ensure the committed
  `DESIGN.md` matches HEAD's actual system (it is already the Glass rewrite in the working
  tree — commit it as the source of truth).
- **Verify every surface** renders under the tokens in both light and dark: chat shell
  (sidebar, header, message list, composer, modals), auth pages, huddle room, flash, empty
  states.
- **Green gate.** `mix precommit` (compile --warnings-as-errors, unused-deps, format, test)
  passes. Commit as a clean baseline before any feature work.

No data-model change in this step; it is purely presentation.

### 0.2 Workspace schema seam

Introduce multi-tenancy structure without any user-facing workspace UI, so Phase 3 becomes
additive rather than a painful backfill across every table.

**New table `workspaces`:**

- `name` — string, required.
- `slug` — string, required, unique.
- timestamps `utc_datetime_usec`.

**`channels` gains:**

- `workspace_id` — FK → `workspaces`, `null: false`, `on_delete: :delete_all`, indexed.
  Migration adds the column nullable, backfills all existing channels (channels **and** DMs)
  to the seeded default workspace, then sets `null: false`.

**Context / behavior:**

- `Chat.default_workspace!/0` — idempotent get-or-create of the single default workspace
  (slug `"tenderr"`, name from config; race-safe like `ensure_general_channel!/0`).
- `ensure_general_channel!/0` and `create_channel/2` set `workspace_id` to the current
  workspace (the default one for now).
- `list_joined_channels/1`, `list_browsable_channels/1` scope by the current workspace.
- `ChatLive` resolves `current_workspace` once at mount (the default workspace). No switcher.
- Seeds ensure the default workspace exists and owns `#general`.

DMs keep `kind: :dm`; they also carry `workspace_id` (the default workspace) for uniformity —
cross-workspace DMs are out of scope until Phase 3.

**Tests:** default workspace is idempotent; created channels belong to the workspace; listings
are workspace-scoped; the backfill migration is covered by the existing suite staying green.

---

## Phase 1 — Messaging depth

All new columns use `utc_datetime_usec` (Chat-context convention). Authorization stays at the
`Chat` context boundary. Broadcasts stay on the existing per-channel topic
`"chat:channel:#{id}"`.

### 1.1 Data model

**`messages` — add columns:**

| Column | Type | Notes |
|---|---|---|
| `parent_message_id` | FK → `messages`, nullable, `on_delete: :delete_all` | thread parent; `NULL` = root message |
| `reply_count` | integer, `null: false`, default `0` | denormalized count of replies to this message |
| `last_reply_at` | `utc_datetime_usec`, nullable | timestamp of the newest reply; drives "last reply …" |
| `edited_at` | `utc_datetime_usec`, nullable | set on edit; renders "(edited)" |
| `deleted_at` | `utc_datetime_usec`, nullable | soft-delete tombstone marker |
| `also_sent_to_channel` | boolean, `null: false`, default `false` | a reply that also appears in the main timeline |

Indexes: `index(:messages, [:parent_message_id, :id])` for thread pagination. The existing
`index(:messages, [:channel_id, :id])` remains for the timeline.

`Message.changeset/2` extended to permit `parent_message_id` and `also_sent_to_channel` on
insert; body validation (trim, 1–4000) unchanged. A separate `edit_changeset/2` casts only
`body` (+ stamps `edited_at`).

**`message_reactions` — relax to arbitrary emoji:**

- Drop the fixed 8-emoji palette guard in the context. Add a real
  `MessageReaction.changeset/2` validating `emoji` as a single emoji grapheme
  (`String.graphemes/1` length check) with a small length cap (≤ 16 bytes), plus
  `unique_constraint([:message_id, :user_id, :emoji])`. The DB unique index is unchanged.

**Typing indicators:** no schema — ephemeral PubSub only.

### 1.2 `Chat` context

**Threads:**

- `send_message/3` accepts an optional `parent_message_id` (and `also_sent_to_channel`) in
  `attrs`. When a `parent_message_id` is present:
  - validate the parent exists and belongs to the same channel;
  - insert the reply, then atomically bump the parent via
    `Repo.update_all(inc: [reply_count: 1], set: [last_reply_at: now])`;
  - broadcast `{:new_message, reply}` **and** `{:message_updated, reloaded_parent}` (so the
    timeline updates the parent's "N replies" affordance).
- `list_thread_replies/2` — `(parent_message, opts)` → replies ascending, `:user` and
  `:reactions` preloaded, cursor pagination like `list_messages/2`.
- `list_messages/2` — timeline query gains
  `where: is_nil(m.parent_message_id) or m.also_sent_to_channel == true` so thread replies are
  hidden from the main list (unless explicitly "also sent to channel").

**Edit / delete (author-only):**

- `update_message/3` — `(user, message, attrs)`; returns `{:error, :unauthorized}` if
  `message.user_id != user.id`; on success stamps `edited_at`, broadcasts
  `{:message_updated, message}`.
- `delete_message/2` — `(user, message)`; author-only (Phase 3 adds admin override); sets
  `deleted_at`, broadcasts `{:message_deleted, message}`. Soft delete: the row and any thread
  replies are retained; the parent renders as a tombstone.

**Reactions:** `toggle_reaction/3` now accepts any valid emoji (validated via the changeset),
still membership-gated, still broadcasts `{:reaction_changed, message}`.
`reaction_palette/0` remains as the quick-access shortlist for the UI.

**Typing:** `broadcast_typing/2` — `(user, channel)` broadcasts an ephemeral
`{:typing, %{user_id: id, username: name}}` on the channel topic. Nothing is persisted.

**Markdown:** `render_markdown/1` — `(body :: String.t()) :: Phoenix.HTML.safe()` renders a
Slack-lite subset via MDEx with sanitization on (see §1.5). Called from the message component;
never stored.

**Unread rule:** `memberships_with_unread/2` and `unread_count/2` count only root messages
(`parent_message_id IS NULL`) newer than `last_read_at` and not authored by the user. Thread
replies do not inflate channel badges (thread-reply unread → Phase 2 activity inbox). A reply
flagged `also_sent_to_channel` still has a `parent_message_id`, so it is visible in the
timeline but — by this rule — deliberately does **not** count toward the channel unread badge.

### 1.3 Broadcast contract (topic `"chat:channel:#{id}"`)

| Event | Emitted by | Payload |
|---|---|---|
| `{:new_message, msg}` | `send_message/3` | `%Message{user: …, reactions: []}`; may carry `parent_message_id`/`also_sent_to_channel` |
| `{:message_updated, msg}` | `update_message/3`, thread reply bump | reloaded `%Message{user, reactions}` (carries `edited_at`, `reply_count`, `last_reply_at`) |
| `{:message_deleted, msg}` | `delete_message/2` | `%Message{deleted_at: …}` (clients render tombstone) |
| `{:reaction_changed, msg}` | `toggle_reaction/3` | reloaded `%Message{user, reactions}` |
| `{:typing, %{user_id, username}}` | `broadcast_typing/2` | ephemeral; receivers show for a few seconds |

### 1.4 LiveView / UI (`ChatLive` + components)

- **Message actions menu.** Expand the existing hover toolbar to: React · Reply in thread ·
  Edit (author only) · Delete (author only) · Copy. Non-authors never see Edit/Delete.
- **Thread side panel.** A right-hand panel (assign `thread_parent` + a dedicated
  `:thread_messages` stream). The main timeline shows a "💬 N replies · last reply <time>"
  affordance under any message with `reply_count > 0`; clicking opens the panel. The panel has
  its own composer; sending posts with `parent_message_id` set. An optional **"Also send to
  #channel"** checkbox sets `also_sent_to_channel`. A reply appends to the panel and, via
  `{:message_updated, parent}`, updates the affordance in the timeline live.
- **Inline edit.** Choosing Edit swaps the message body for an inline composer (save/cancel).
  Save calls `update_message/3`; the update arrives for everyone via `{:message_updated}`.
  Edited messages render a subtle "(edited)".
- **Delete.** A confirm dialog → `delete_message/2`; the message renders as a tombstone
  ("This message was deleted") for everyone via `{:message_deleted}`.
- **Markdown rendering.** Message bodies render bold / italic / strikethrough / inline code /
  fenced code blocks / blockquote / lists / links; bare URLs autolinked. The composer stays a
  plain-text textarea that accepts those syntaxes.
- **Full emoji picker.** A searchable, categorized picker (LiveComponent, §1.5) powers both
  arbitrary-emoji **reactions** and **composer** insertion. The quick 8-emoji row stays as
  fast access with a "＋" that opens the full picker.
- **Typing indicators.** `ComposerKeys` emits a debounced `typing` event on input (at most
  once per ~2s). `ChatLive` rebroadcasts via `broadcast_typing/2`, tracks transient
  `typing_users` with a per-user TTL (`Process.send_after` ~4s auto-clear, also cleared on
  that user's `:new_message`), and renders "X is typing…" beneath the message list. A user
  never sees their own typing.
- **Unread divider.** At open, capture the membership's `last_read_at` **before** `mark_read`
  into `unread_boundary_at`; render a "New" divider above the first message newer than it and
  not authored by the current user. Add "Jump to unread" (JS scroll to the divider) and "Mark
  all as read" (calls `mark_read`, clears the divider).

**Streams / `entry_meta`.** Streams can't be read back, so `ChatLive` keeps its parallel
`entry_meta` map; it gains `edited`, `deleted`, and `reply_count`/`last_reply_at` so grouping
and affordances re-render correctly on updates. The thread panel is a separate stream with its
own lightweight grouping.

### 1.5 Tech choices (assets are npm-free / pure esbuild)

- **Markdown → MDEx** (`{:mdex, "~> 0.x"}`): Rust comrak parser + built-in `ammonia`
  HTML sanitizer. Configured to a Slack-lite feature set — enable emphasis, strong,
  strikethrough, inline/fenced code, blockquote, lists, autolinks; **disable** raw HTML,
  images, and tables; sanitize output. Pure Elixir dependency — no npm, works with the
  existing esbuild pipeline. Rendered on the fly in the message component (cheap; no storage).
- **Emoji picker → vendored dataset + LiveComponent.** Ship a curated emoji dataset
  (`priv/emoji/emoji.json`, ~1500–1900 emoji with category + keywords), loaded into a
  `PhoenixChat.Emoji` module at compile time. A `EmojiPickerComponent` (LiveComponent) renders
  categories and does **server-side** substring search over names/keywords. No JS library, no
  npm. Reused by both the reaction affordance and the composer.

### 1.6 Error handling

- Author-only edit/delete enforced in the **context** (`{:error, :unauthorized}`), not merely
  hidden in the UI; the LiveView also hides the affordances for non-authors as UX.
- Edit reuses body validation (trim, 1–4000); failures render on the inline edit form.
- Thread reply to a non-existent / cross-channel parent → validation error, never a 500.
- A deleted parent that has replies keeps its tombstone and its thread remains readable.
- Markdown output is sanitized (ammonia) — no raw HTML / script injection from message bodies.
- Reaction emoji validated server-side (single grapheme, length cap); invalid → changeset
  error, no broadcast.
- Typing is best-effort ephemeral; a dropped typing broadcast self-heals on the TTL.
- LV reconnect self-heals: a fresh mount reloads sidebar, timeline, and (if open) the thread
  from the DB.

### 1.7 Testing

**Context (`Chat`):**
- Threads: reply sets `parent_message_id`, bumps parent `reply_count` + `last_reply_at`;
  `list_thread_replies/2` paginates; timeline excludes replies unless `also_sent_to_channel`.
- Edit: author-only (`{:error, :unauthorized}` for others), stamps `edited_at`, broadcasts
  `{:message_updated}`.
- Delete: soft (row retained, `deleted_at` set), broadcasts `{:message_deleted}`, non-author
  rejected.
- Reactions: arbitrary emoji accepted; invalid emoji rejected via changeset; toggle add/remove
  still deduped.
- Unread: root messages only — a thread reply does not increment a channel's unread.
- Markdown: bold/italic/code/link render; raw HTML/script sanitized away.
- Typing: `broadcast_typing/2` delivers `{:typing, …}` to a subscribed process.

**LiveView (`ChatLive`):**
- Thread panel opens from the affordance; a reply appears in the panel and the parent's reply
  count updates in the timeline for a second connected LV.
- Inline edit updates the body + shows "(edited)" for a second LV.
- Delete shows the tombstone for a second LV.
- Emoji picker: searching + picking an arbitrary emoji adds a reaction chip.
- Typing: a second connected LV shows "X is typing…" when the first types.
- Unread divider renders above the first unread on open; "Mark all as read" clears it.

Gate every task on `mix test`; final task gate `mix precommit`.

### 1.8 Explicitly deferred (later phases, not Phase 1)

@mentions + notifications, full-text search, file/image uploads (Phase 2); pinned & saved
items, private channels, roles/permissions, channel & member management, per-message read
receipts, user profiles & status (Phase 3); slash commands, drafts, scheduled messages,
link unfurling/previews, thread-level unread. Huddle hardening (directed signaling, rate
limiting, payload caps, DM-slug huddle guard, SFU/TURN scale) tracked separately from the
messaging roadmap.

## 2. Implementation order (high level — detailed plan follows in writing-plans)

**Phase 0**
1. Land the Glass theme: track Inter fonts, delete dead Plex/daisyUI assets, fix moduledoc &
   `DESIGN.md`, verify all surfaces light+dark, `mix precommit` green, commit.
2. Workspace seam: migration (`workspaces` + `channels.workspace_id` with backfill),
   `default_workspace!/0`, scope listings, seeds, tests green.

**Phase 1**
3. Migration: message thread/edit/delete columns + indexes; `message_reactions` changeset;
   schema updates.
4. `Chat` context: threads (`send_message` parent handling, `list_thread_replies`),
   edit/delete, arbitrary-emoji reactions, root-only unread — with context tests.
5. MDEx dependency + `render_markdown/1` + sanitized rendering in the message component.
6. Emoji dataset + `PhoenixChat.Emoji` + `EmojiPickerComponent` (reactions + composer).
7. `ChatLive`: message actions menu, inline edit, delete + tombstone — with LV tests.
8. Thread side panel (stream, composer, "N replies" affordance, "also send to channel") —
   with LV tests.
9. Typing indicators (`ComposerKeys` emit, TTL clear, render) — with LV test.
10. Unread divider (`unread_boundary_at`, "Jump to unread", "Mark all as read") — with LV test.
11. Gettext sweep for new strings (sr translations); final `mix precommit`.
