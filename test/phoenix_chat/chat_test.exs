defmodule PhoenixChat.ChatTest do
  use PhoenixChat.DataCase, async: true

  alias PhoenixChat.Chat
  alias PhoenixChat.Chat.Channel
  alias PhoenixChat.Chat.Workspace

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

  describe "join_public_channel/2" do
    test "joins a public channel and returns it" do
      creator = user_fixture()
      joiner = user_fixture()
      ch = channel_fixture(creator)

      result = Chat.join_public_channel(joiner, ch.id)
      assert result.id == ch.id
      assert Chat.member?(joiner, ch)
    end

    test "raises Ecto.NoResultsError when given a DM channel id" do
      a = user_fixture()
      b = user_fixture()
      dm = Chat.get_or_create_dm!(a, b)
      stranger = user_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Chat.join_public_channel(stranger, dm.id)
      end

      refute Chat.member?(stranger, dm)
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
        Repo.all(from m in PhoenixChat.Chat.ChannelMembership, where: m.channel_id == ^ch.id)

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

  describe "direct messages" do
    test "get_or_create_dm!/2 creates once and dedups both orderings" do
      a = user_fixture()
      b = user_fixture()

      dm1 = Chat.get_or_create_dm!(a, b)
      dm2 = Chat.get_or_create_dm!(b, a)

      assert dm1.id == dm2.id
      assert dm1.kind == :dm
      assert dm1.dm_key == "#{Enum.min([a.id, b.id])}:#{Enum.max([a.id, b.id])}"
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

  describe "messages" do
    setup do
      user = user_fixture()
      channel = channel_fixture(user)
      %{user: user, channel: channel}
    end

    test "send_message/3 stores, trims, preloads user and broadcasts", %{
      user: user,
      channel: channel
    } do
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

    test "list_messages/2 returns ascending with cursor pagination", %{
      user: user,
      channel: channel
    } do
      for i <- 1..7, do: message_fixture(user, channel, %{body: "poruka #{i}"})

      {page, cursor} = Chat.list_messages(channel, limit: 5)
      assert Enum.map(page, & &1.body) == for(i <- 3..7, do: "poruka #{i}")
      assert cursor == List.first(page).id

      {older, older_cursor} = Chat.list_messages(channel, limit: 5, before_id: cursor)
      assert Enum.map(older, & &1.body) == ["poruka 1", "poruka 2"]
      assert older_cursor == nil
    end
  end

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
  end

  describe "reactions" do
    setup do
      user = user_fixture()
      channel = channel_fixture(user)
      message = message_fixture(user, channel)
      %{user: user, channel: channel, message: message}
    end

    test "toggle adds then removes, and broadcasts", %{
      user: user,
      channel: channel,
      message: message
    } do
      :ok = Chat.subscribe(channel)

      assert :ok = Chat.toggle_reaction(user, message, "👍")
      assert_receive {:reaction_changed, %{id: mid, reactions: [%{emoji: "👍"}]}}
      assert mid == message.id

      assert :ok = Chat.toggle_reaction(user, message, "👍")
      assert_receive {:reaction_changed, %{reactions: []}}
    end

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
end
