defmodule PhoenixChat.Markdown do
  @moduledoc """
  Slack-lite Markdown rendering backed by MDEx.

  Supports emphasis, strong, strikethrough, inline and fenced code,
  blockquotes, lists and autolinks. Raw HTML, images and tables are
  stripped so message bodies can never inject markup.
  """

  # Tags the default sanitizer allows that we deliberately drop for Slack-lite.
  @blocked_tags ~w(img table thead tbody tr td th)

  @extension [strikethrough: true, autolink: true]
  @render [unsafe: true]

  @doc """
  Renders `body` to sanitized, safe HTML.

  Returns a `t:Phoenix.HTML.safe/0` tuple ready to interpolate in a HEEx
  template. Raw HTML is parsed and then cleaned by the sanitizer, so
  disallowed markup (scripts, images, tables, iframes, ...) is removed
  rather than escaped.
  """
  def render(body) when is_binary(body) do
    body
    |> MDEx.to_html!(extension: @extension, render: @render, sanitize: sanitize_options())
    |> Phoenix.HTML.raw()
  end

  defp sanitize_options do
    MDEx.Document.default_sanitize_options()
    |> Keyword.update(:rm_tags, @blocked_tags, &(&1 ++ @blocked_tags))
  end
end
