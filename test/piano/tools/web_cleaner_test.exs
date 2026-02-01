defmodule Piano.Tools.WebCleanerTest do
  use ExUnit.Case, async: true

  alias Piano.Tools.WebCleaner

  describe "clean/2" do
    test "extracts text from simple HTML" do
      html = """
      <html>
        <head><title>Test Page</title></head>
        <body>
          <h1>Hello World</h1>
          <p>This is a test paragraph.</p>
        </body>
      </html>
      """

      assert {:ok, content} = WebCleaner.clean(html, :text)
      assert content =~ "Hello World"
      assert content =~ "This is a test paragraph"
    end

    test "removes noise elements" do
      html = """
      <html>
        <body>
          <script>alert('test');</script>
          <nav>Navigation</nav>
          <main>
            <h1>Main Content</h1>
            <p>Important text here.</p>
          </main>
          <footer>Footer content</footer>
        </body>
      </html>
      """

      assert {:ok, content} = WebCleaner.clean(html, :text)
      assert content =~ "Main Content"
      assert content =~ "Important text here"
      refute content =~ "alert"
      refute content =~ "Navigation"
      refute content =~ "Footer"
    end

    test "converts to markdown" do
      html = """
      <html>
        <body>
          <main>
            <h1>Title</h1>
            <h2>Subtitle</h2>
            <p>A paragraph with <strong>bold</strong> and <em>italic</em> text.</p>
            <ul>
              <li>Item 1</li>
              <li>Item 2</li>
            </ul>
          </main>
        </body>
      </html>
      """

      assert {:ok, content} = WebCleaner.clean(html, :markdown)
      assert content =~ "# Title"
      assert content =~ "## Subtitle"
      assert content =~ "**bold**"
      assert content =~ "*italic*"
      assert content =~ "- Item 1"
      assert content =~ "- Item 2"
    end

    test "returns raw HTML when format is html" do
      html = "<html><body><h1>Test</h1></body></html>"

      assert {:ok, content} = WebCleaner.clean(html, :html)
      assert content =~ "<h1>Test</h1>"
    end

    test "handles malformed HTML gracefully" do
      html = "<p>Unclosed paragraph"

      assert {:ok, content} = WebCleaner.clean(html, :text)
      assert is_binary(content)
    end
  end

  describe "normalize_whitespace/1" do
    test "collapses multiple spaces" do
      result = WebCleaner.normalize_whitespace("hello    world")
      assert result == "hello world"
    end

    test "collapses multiple newlines" do
      result = WebCleaner.normalize_whitespace("line1\n\n\n\nline2")
      assert result == "line1\n\nline2"
    end

    test "trims whitespace" do
      result = WebCleaner.normalize_whitespace("  hello world  ")
      assert result == "hello world"
    end
  end
end
