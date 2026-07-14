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
