defmodule PhoenixChatWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by channel tests.

  Such tests rely on `Phoenix.ChannelTest` and also import other
  functionality to make it easier to build common data structures and
  interact with channels.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import PhoenixChatWeb.ChannelCase

      # The default endpoint for testing
      @endpoint PhoenixChatWeb.Endpoint
    end
  end

  setup tags do
    PhoenixChat.DataCase.setup_sandbox(tags)
    :ok
  end
end
