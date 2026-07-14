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
