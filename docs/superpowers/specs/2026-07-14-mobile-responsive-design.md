# Mobile-responsive chat shell — design

Date: 2026-07-14

## Problem

`ChatLive` renders a fixed 3-column desktop layout: a 256px sidebar
(channels/DMs), a flexible chat column, and an optional 384px thread panel
(`lib/phoenix_chat_web/live/chat_live.html.heex`,
`lib/phoenix_chat_web/live/chat_live/components.ex`). None of it adapts below
desktop widths — on a phone all three columns would render squeezed side by
side. The app has no responsive treatment for the chat shell today (only the
auth pages use `sm:` breakpoints).

## Goals

- Below the `md` (768px) breakpoint, show exactly one of {conversation list,
  chat, thread} at a time, Slack-mobile style, with a back affordance to
  return to the list.
- At `md` and above, preserve the current 3-column desktop layout unchanged.
- No new client-side state duplication — visibility is derived from existing
  server assigns (`@active`, `@thread_parent`) plus one new ephemeral UI
  assign, following the codebase's existing pattern for panel visibility
  (`@show_dm_modal`, `@show_create_modal`, `@show_browse_modal`).

## Non-goals

- Redesigning modals, the emoji picker layout, or touch-target sizing beyond
  a couple of narrow-viewport safety tweaks called out below.
- Any change to desktop (`md:` and up) visuals or behavior.
- A dedicated mobile route/URL scheme. Navigation stays patch-based, exactly
  as today.

## State model

Add one new assign, initialized in `mount/3` alongside the other ephemeral UI
booleans:

- `mobile_sidebar_open` (boolean, default `false`)

This is the only new state. Combined with the existing `@active` and
`@thread_parent`, panel visibility on mobile is fully determined:

| Panel    | Visible on mobile (`< md`) when                          | Visible on `md:` and up |
|----------|------------------------------------------------------------|--------------------------|
| Sidebar  | `@mobile_sidebar_open` or `is_nil(@active)`                | always                   |
| Chat     | not sidebar-visible and not `@thread_parent`                | always                   |
| Thread   | `@thread_parent` present (unconditional — panel isn't rendered otherwise) | rendered alongside chat, as today |

`is_nil(@active)` is included defensively (e.g. a user with no joined
channels) even though the current `:index` route always redirects to
`/c/general`.

### Transitions

- **Open sidebar (mobile back button)**: new `phx-click="open_mobile_sidebar"`
  handler sets `mobile_sidebar_open: true`.
- **Pick a channel/DM**: the existing `.link patch={~p"/c/#{slug}"}` /
  `patch={~p"/dm/#{username}"}` flow already runs through
  `open_conversation/2`. Add `mobile_sidebar_open: false` to the assigns set
  there, so selecting a conversation always returns to the chat view on
  mobile — no separate "close" event needed.
- **Open thread**: existing `open_thread` handler, unchanged. Thread simply
  renders full-width on mobile via responsive width classes.
- **Close thread (back from thread to chat)**: existing `close_thread`
  handler and its "×" button, unchanged — already returns the user to the
  chat panel.

No new events are needed beyond `open_mobile_sidebar`.

## Layout changes

All changes are Tailwind responsive utility classes; no new JS hooks.

**`<aside>` (sidebar)** in `chat_live.html.heex`:
- Width: `w-full md:w-64` (was `w-64`).
- Display: `hidden` unless visible-per-table above, `md:flex` always.

**`<section>` (chat column)**:
- Display: `hidden` unless visible-per-table above, `md:flex` always. Width
  is already handled by `flex-1` once hidden siblings stop taking flex
  space — no explicit mobile width class needed.

**`<.thread_panel>` (`components.ex`)**:
- Width: `w-full md:w-96` (was `w-96`).
- No visibility class changes needed — it's only rendered at all when
  `@active && @thread_parent` (existing `:if`).

**`<.channel_header>` (`components.ex`)**:
- Add a leading back button, `md:hidden`, `hero-arrow-left` icon,
  `phx-click="open_mobile_sidebar"`, matching the existing `.icon_button`
  styling used elsewhere in the header.

## Polish

- `EmojiPickerComponent` root div is fixed `w-72` (288px); add `max-w-full`
  as a safety net so it can't overflow the viewport on the narrowest phones
  (~320px wide, after the emoji-picker overlay's `px-4` gutters).
- No changes needed to `cds_modal`, the composer, or the message list — they
  already use fluid/max-width classes (`px-4`, `max-w-md`, `max-w-3xl`) that
  work at phone widths.

## Testing

- Existing `ChatLive` LiveView tests are unaffected (no assign renamed, no
  event removed).
- Add a test asserting `mobile_sidebar_open` starts `false`, flips to `true`
  on `open_mobile_sidebar`, and flips back to `false` after patching to a
  channel via `open_conversation/2`.
- Manual verification: resize/emulate a phone-width viewport (see `verify`
  skill) and confirm: list → chat → thread → back → back navigation works,
  and desktop (`md:`+) layout is pixel-identical to before.
