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

    test "channel header links to the huddle", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/c/general")
      assert has_element?(view, ~s{#huddle-link[href="/huddle/general"]})
    end

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
  end

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

    test "join_channel event with a DM id is rejected and membership is unchanged", %{
      conn: conn,
      user: user
    } do
      other1 = user_fixture()
      other2 = user_fixture()
      dm = Chat.get_or_create_dm!(other1, other2)

      {:ok, view, _html} = live(conn, ~p"/c/general")

      render_hook(view, "join_channel", %{"channel-id" => to_string(dm.id)})

      refute Chat.member?(user, dm)
      assert render(view) =~ "does not exist or cannot be joined"
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

    test "typing signal from a different channel is not shown to a viewer on another channel", %{
      conn: conn,
      user: user
    } do
      other = user_fixture()
      general = Chat.get_channel_by_slug!("general")
      # Both users are members of general AND of a second channel.
      second_channel = channel_fixture(user, %{name: "drugikanal"})
      {:ok, _} = Chat.join_channel(other, second_channel)
      {:ok, _} = Chat.join_channel(other, general)

      # Viewer sits on #general.
      {:ok, view, _html} = live(conn, ~p"/c/general")

      # Other user is typing in the SECOND channel — viewer must NOT see typing.
      :ok = Chat.broadcast_typing(other, second_channel)

      refute has_element?(view, ".cds-typing")
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
  end

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

  describe "thread panel" do
    setup :register_and_log_in_user

    test "open_thread is silently ignored for a message in a foreign channel", %{
      conn: conn,
      user: _user
    } do
      # A different user owns a channel the viewer has never joined.
      foreign_owner = user_fixture()
      foreign_channel = channel_fixture(foreign_owner, %{name: "tudjikanalthread"})
      foreign_message = message_fixture(foreign_owner, foreign_channel, %{body: "tajna nit"})

      {:ok, view, _html} = live(conn, ~p"/c/general")

      # Fire the event with the foreign message id — must be a no-op.
      render_hook(view, "open_thread", %{"message-id" => to_string(foreign_message.id)})

      refute has_element?(view, "#thread-panel")
      refute render(view) =~ "tajna nit"
    end

    test "open_thread works normally for a message in the active channel", %{
      conn: conn,
      user: user
    } do
      general = Chat.get_channel_by_slug!("general")
      parent = message_fixture(user, general, %{body: "autorizovana nit"})

      {:ok, view, _html} = live(conn, ~p"/c/general")
      render_hook(view, "open_thread", %{"message-id" => to_string(parent.id)})

      assert has_element?(view, "#thread-panel")
      assert has_element?(view, "#thread-panel", "autorizovana nit")
    end

    test "opens the thread panel from the reply affordance and shows existing replies", %{
      conn: conn,
      user: user
    } do
      general = Chat.get_channel_by_slug!("general")
      parent = message_fixture(user, general, %{body: "korenska poruka"})

      {:ok, _} =
        Chat.send_message(user, general, %{
          "body" => "prvi odgovor",
          "parent_message_id" => parent.id
        })

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
        Chat.send_message(user, general, %{
          "body" => "prvi odgovor",
          "parent_message_id" => parent.id
        })

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

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() ->
        :ok

      tries == 0 ->
        flunk("condition not met within retries")

      true ->
        Process.sleep(10)
        eventually(fun, tries - 1)
    end
  end
end
