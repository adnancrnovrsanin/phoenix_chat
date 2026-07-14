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
