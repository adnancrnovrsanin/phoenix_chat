defmodule PhoenixChat.ChatFixtures do
  @moduledoc """
  Test helpers for creating PhoenixChat.Chat entities.
  """

  alias PhoenixChat.Chat

  def unique_channel_name, do: "kanal-#{System.unique_integer([:positive])}"

  def channel_fixture(creator, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{name: unique_channel_name()})
    {:ok, channel} = Chat.create_channel(creator, attrs)
    channel
  end
end
