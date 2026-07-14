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
