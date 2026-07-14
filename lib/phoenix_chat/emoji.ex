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
