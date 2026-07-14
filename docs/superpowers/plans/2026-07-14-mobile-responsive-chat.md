# Mobile-Responsive Chat Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the 3-column chat shell (sidebar / chat / thread) show one panel at a time below the `md` (768px) breakpoint, Slack-mobile style, with a back button to return to the conversation list, while leaving the desktop layout pixel-identical.

**Architecture:** Panel visibility on mobile is derived purely from existing server assigns (`@active`, `@thread_parent`) plus one new ephemeral UI assign (`@mobile_sidebar_open`), rendered as Tailwind responsive `hidden`/`flex` classes. No new JS hooks, no client-side state duplication.

**Tech Stack:** Phoenix LiveView, HEEx, Tailwind CSS v4 (utility classes only, no config file — see `assets/css/app.css`), ExUnit + `Phoenix.LiveViewTest`.

## Global Constraints

- Follow `AGENTS.md`: wrap `if` inside `{...}` HEEx attribute expressions with parens — `{if(condition, do: "a", else: "b")}`.
- HEEx class attrs with multiple values use list syntax: `class={["base classes", conditional]}`.
- No new dependencies. No changes to desktop (`md:` and up) visuals or behavior.
- Run `mix precommit` before considering the work done (per `AGENTS.md`).

---

## File Structure

- Modify `lib/phoenix_chat_web/live/chat_live.ex` — add `mobile_sidebar_open` assign, `open_mobile_sidebar` event, two small private visibility predicates, reset the assign in `open_conversation/2`.
- Modify `lib/phoenix_chat_web/live/chat_live.html.heex` — responsive classes + ids on the sidebar `<aside>` and chat `<section>`.
- Modify `lib/phoenix_chat_web/live/chat_live/components.ex` — responsive width on `thread_panel/1`, back button in `channel_header/1`.
- Modify `lib/phoenix_chat_web/components/emoji_picker_component.ex` — `max-w-full` safety net on the picker root.
- Modify `test/phoenix_chat_web/live/chat_live_test.exs` — new `describe "mobile layout"` block.
- Modify `test/phoenix_chat_web/components/emoji_picker_component_test.exs` — one extra assertion.

---

### Task 1: Mobile sidebar/chat visibility state + layout

**Files:**
- Modify: `lib/phoenix_chat_web/live/chat_live.ex`
- Modify: `lib/phoenix_chat_web/live/chat_live.html.heex`
- Test: `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: existing assigns `@active` (`Channel.t() | nil`), `@thread_parent` (`Message.t() | nil`), both already set in `mount/3` and `open_conversation/2`.
- Produces: new boolean assign `@mobile_sidebar_open` (default `false`); new `handle_event("open_mobile_sidebar", _params, socket)` clause; new private helpers `mobile_sidebar_visible?/1` and `mobile_chat_visible?/1` (both take `assigns`, return boolean) — Task 2 does not need these, but they must exist and be named exactly this for the template to compile.
- DOM: sidebar `<aside>` gets `id="chat-sidebar"`, chat `<section>` gets `id="chat-main"` — Task 2's tests rely on these exact ids.

- [ ] **Step 1: Write the failing tests**

Open `test/phoenix_chat_web/live/chat_live_test.exs` and add a new `describe` block right after the existing `describe "channel view"` block closes (search for the line that reads `describe "thread panel" do` and insert immediately above it):

```elixir
  describe "mobile layout" do
    setup :register_and_log_in_user

    test "sidebar is hidden and chat is visible on mobile by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      assert has_element?(view, "#chat-sidebar.hidden")
      refute has_element?(view, "#chat-main.hidden")
    end

    test "open_mobile_sidebar shows the sidebar and hides chat", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      render_hook(view, "open_mobile_sidebar", %{})

      refute has_element?(view, "#chat-sidebar.hidden")
      assert has_element?(view, "#chat-main.hidden")
    end

    test "picking a channel closes the mobile sidebar again", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")
      render_hook(view, "open_mobile_sidebar", %{})
      assert has_element?(view, "#chat-main.hidden")

      view |> element(~s{a[href="/c/general"]}) |> render_click()

      assert has_element?(view, "#chat-sidebar.hidden")
      refute has_element?(view, "#chat-main.hidden")
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/phoenix_chat_web/live/chat_live_test.exs`
Expected: the three new tests FAIL — either `has_element?` finds no `#chat-sidebar`/`#chat-main` (they don't have ids yet) or `open_mobile_sidebar` raises `(FunctionClauseError)`/`UndefinedFunctionError` because no matching `handle_event` clause exists. Other existing tests still PASS.

- [ ] **Step 3: Add the assign, event handler, and visibility helpers**

In `lib/phoenix_chat_web/live/chat_live.ex`, find the `mount/3` assign list (starts around line 36 with `|> assign(`) and add `mobile_sidebar_open: false,` right after `gate?: false,`:

```elixir
       gate?: false,
       mobile_sidebar_open: false,
       show_create_modal: false,
```

Find `open_conversation/2` (around line 641) and add `mobile_sidebar_open: false,` to its `assign(...)` call, right after `gate?: false,`:

```elixir
    socket
    |> assign(
      active: channel,
      active_other: other,
      gate?: false,
      mobile_sidebar_open: false,
      conversation_title: title,
```

Find the `close_thread` handler (around line 189-194) and add a new `open_mobile_sidebar` clause right after it:

```elixir
  def handle_event("close_thread", _params, socket) do
    {:noreply,
     socket
     |> assign(thread_parent: nil, thread_form: thread_form())
     |> stream(:thread_messages, [], reset: true)}
  end

  def handle_event("open_mobile_sidebar", _params, socket) do
    {:noreply, assign(socket, mobile_sidebar_open: true)}
  end
```

Near the bottom of the module, alongside the other small private helpers (e.g. next to `defp conversation_title/2`), add:

```elixir
  defp mobile_sidebar_visible?(assigns),
    do: assigns.mobile_sidebar_open or is_nil(assigns.active)

  defp mobile_chat_visible?(assigns),
    do: !mobile_sidebar_visible?(assigns) and is_nil(assigns.thread_parent)
```

- [ ] **Step 4: Update the template classes**

In `lib/phoenix_chat_web/live/chat_live.html.heex`, replace the sidebar opening tag (line 2):

```heex
  <aside class="flex w-64 flex-none flex-col border-r border-border">
```

with:

```heex
  <aside
    id="chat-sidebar"
    class={[
      "w-full flex-none flex-col border-r border-border md:w-64",
      if(mobile_sidebar_visible?(assigns), do: "flex", else: "hidden md:flex")
    ]}
  >
```

Replace the chat section opening tag (line 90):

```heex
  <section class="flex min-w-0 flex-1 flex-col">
```

with:

```heex
  <section
    id="chat-main"
    class={[
      "min-w-0 flex-1 flex-col",
      if(mobile_chat_visible?(assigns), do: "flex", else: "hidden md:flex")
    ]}
  >
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/phoenix_chat_web/live/chat_live_test.exs`
Expected: PASS — all tests in the file, including the three new ones.

- [ ] **Step 6: Commit**

```bash
git add lib/phoenix_chat_web/live/chat_live.ex lib/phoenix_chat_web/live/chat_live.html.heex test/phoenix_chat_web/live/chat_live_test.exs
git commit -m "Add mobile sidebar/chat single-panel visibility"
```

---

### Task 2: Thread panel mobile width + back button

**Files:**
- Modify: `lib/phoenix_chat_web/live/chat_live/components.ex`
- Test: `test/phoenix_chat_web/live/chat_live_test.exs`

**Interfaces:**
- Consumes: `mobile_sidebar_visible?/1` is NOT reused here (components.ex is a separate module with no access to chat_live.ex's private functions) — the back button just fires the existing `"open_mobile_sidebar"` event by name, and ids `#chat-sidebar` / `#chat-main` / `#thread-panel` from Task 1 and the existing `thread_panel/1`.
- Produces: nothing new consumed by later tasks.

- [ ] **Step 1: Write the failing tests**

In `test/phoenix_chat_web/live/chat_live_test.exs`, add these tests inside the `describe "mobile layout"` block added in Task 1 (after the "picking a channel closes..." test):

```elixir
    test "back button in the header reopens the sidebar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")

      view |> element("#mobile-back-button") |> render_click()

      refute has_element?(view, "#chat-sidebar.hidden")
      assert has_element?(view, "#chat-main.hidden")
    end

    test "opening a thread hides chat on mobile, closing it restores chat", %{
      conn: conn,
      user: user
    } do
      general = Chat.get_channel_by_slug!("general")
      parent = message_fixture(user, general, %{body: "korenska poruka za mobilni"})

      {:ok, view, _html} = live(conn, ~p"/c/general")

      render_hook(view, "open_thread", %{"message-id" => to_string(parent.id)})
      assert has_element?(view, "#thread-panel")
      assert has_element?(view, "#chat-main.hidden")

      view |> element("#close-thread") |> render_click()
      refute has_element?(view, "#thread-panel")
      refute has_element?(view, "#chat-main.hidden")
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/phoenix_chat_web/live/chat_live_test.exs`
Expected: the back-button test FAILS — `element("#mobile-back-button")` finds no matching element, since the button doesn't exist yet. The thread test PASSES already: `mobile_chat_visible?/1` from Task 1 already reacts to `@thread_parent`, so `#chat-main.hidden` is already correct once a thread is open — this test just locks that behavior in.

- [ ] **Step 3: Add the back button and thread panel width**

In `lib/phoenix_chat_web/live/chat_live/components.ex`, find `channel_header/1` (around line 281-308) and add a back button as the first child of `<header>`:

```elixir
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
```

(the rest of the function body is unchanged — only the new `<.icon_button>` block is inserted right after the `<header ...>` opening tag and before the existing `<div :if={@other} ...>`.)

Find `thread_panel/1` (around line 407-409) and change the outer `<aside>` class:

```elixir
    <aside id="thread-panel" class="flex w-96 flex-none flex-col border-l border-border">
```

to:

```elixir
    <aside id="thread-panel" class="flex w-full flex-none flex-col border-l border-border md:w-96">
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/phoenix_chat_web/live/chat_live_test.exs`
Expected: PASS — all tests in the file.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_chat_web/live/chat_live/components.ex test/phoenix_chat_web/live/chat_live_test.exs
git commit -m "Add mobile back button and full-width thread panel"
```

---

### Task 3: Emoji picker narrow-viewport safety net

**Files:**
- Modify: `lib/phoenix_chat_web/components/emoji_picker_component.ex`
- Test: `test/phoenix_chat_web/components/emoji_picker_component_test.exs`

**Interfaces:**
- Consumes: nothing from Tasks 1-2.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test**

In `test/phoenix_chat_web/components/emoji_picker_component_test.exs`, add a test after the existing `"renders a search box and an emoji grid"` test:

```elixir
  test "root element caps at the viewport width on narrow screens" do
    html =
      render_component(PhoenixChatWeb.EmojiPickerComponent, id: "emoji-picker", target: :reaction)

    assert html =~ "max-w-full"
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/phoenix_chat_web/components/emoji_picker_component_test.exs`
Expected: FAIL — `max-w-full` not found in the rendered HTML.

- [ ] **Step 3: Add the class**

In `lib/phoenix_chat_web/components/emoji_picker_component.ex`, find:

```elixir
    <div id={@id} class="flex w-72 flex-col gap-2">
```

and change it to:

```elixir
    <div id={@id} class="flex w-72 max-w-full flex-col gap-2">
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/phoenix_chat_web/components/emoji_picker_component_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/phoenix_chat_web/components/emoji_picker_component.ex test/phoenix_chat_web/components/emoji_picker_component_test.exs
git commit -m "Cap emoji picker width on narrow viewports"
```

---

### Task 4: Full test suite, precommit, and manual verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: PASS, 0 failures.

- [ ] **Step 2: Run precommit**

Run: `mix precommit`
Expected: compiles with no warnings, formatter clean, all tests pass. Fix anything it flags before continuing.

- [ ] **Step 3: Manual verification in a phone-width viewport**

Run: `mix phx.server`, open `http://localhost:4000` in a browser, log in, then open devtools' responsive/device toolbar and set the viewport to 375×667 (iPhone SE-class width — below the 768px `md` breakpoint).

Walk through and confirm:
1. Only the chat panel is visible (no sidebar, no thread panel); the header shows a back arrow on the left.
2. Tap the back arrow → the conversation list (sidebar) fills the screen, chat is gone.
3. Tap a channel or DM → chat fills the screen again showing that conversation's messages.
4. Open a thread from a message's reply count → the thread panel fills the screen, chat is gone.
5. Tap the thread panel's "×" close button → chat fills the screen again.
6. Widen the viewport back past 768px → sidebar, chat, and (if a thread was open) thread panel are all visible side by side, matching the pre-existing desktop layout exactly.

- [ ] **Step 4: Commit (only if Step 2 required fixes)**

If `mix precommit` required any fixes, stage and commit them:

```bash
git add -A
git commit -m "Fix precommit findings for mobile layout work"
```

If no fixes were needed, skip this step — there is nothing to commit.
