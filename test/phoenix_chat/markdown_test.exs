defmodule PhoenixChat.MarkdownTest do
  use ExUnit.Case, async: true

  alias PhoenixChat.Markdown

  defp html(body), do: body |> Markdown.render() |> Phoenix.HTML.safe_to_string()

  describe "render/1" do
    test "returns a Phoenix.HTML safe tuple" do
      assert {:safe, _iodata} = Markdown.render("hello")
    end

    test "renders strong emphasis" do
      assert html("**bold**") =~ "<strong>bold</strong>"
    end

    test "renders regular emphasis" do
      assert html("_italic_") =~ "<em>italic</em>"
    end

    test "renders strikethrough" do
      assert html("~~gone~~") =~ "<del>gone</del>"
    end

    test "renders inline code" do
      assert html("`inline`") =~ "<code>inline</code>"
    end

    test "renders fenced code blocks" do
      out = html("```\nline\n```")
      assert out =~ "<pre>"
      assert out =~ "<code"
      assert out =~ "line"
    end

    test "renders explicit links" do
      out = html("[Elixir](https://elixir-lang.org)")
      assert out =~ ~s(href="https://elixir-lang.org")
      assert out =~ ">Elixir</a>"
    end

    test "autolinks bare urls" do
      assert html("see https://elixir-lang.org now") =~ ~s(href="https://elixir-lang.org")
    end

    test "renders blockquotes and lists" do
      assert html("> quote") =~ "<blockquote>"
      assert html("- one\n- two") =~ "<li>one</li>"
    end

    test "strips <script> tags via sanitize" do
      out = html("hi <script>alert('xss')</script>")
      refute out =~ "<script"
      refute out =~ "alert('xss')"
      assert out =~ "hi"
    end

    test "strips raw inline HTML such as <iframe>" do
      refute html(~s(<iframe src="https://evil.test"></iframe>)) =~ "<iframe"
    end

    test "strips images" do
      refute html("![alt](https://example.test/x.png)") =~ "<img"
    end

    test "does not render markdown tables" do
      refute html("| a | b |\n| - | - |\n| 1 | 2 |") =~ "<table"
    end
  end
end
