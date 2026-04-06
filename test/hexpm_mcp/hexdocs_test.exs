defmodule HexpmMcp.HexDocsTest do
  use ExUnit.Case, async: true

  alias HexpmMcp.HexDocs

  describe "html_to_markdown/1" do
    test "converts headings" do
      html = "<h1>Title</h1><h2>Subtitle</h2><h3>Section</h3>"
      md = HexDocs.html_to_markdown(html)
      assert md =~ "# Title"
      assert md =~ "## Subtitle"
      assert md =~ "### Section"
    end

    test "converts paragraphs" do
      html = "<p>Hello world</p><p>Second paragraph</p>"
      md = HexDocs.html_to_markdown(html)
      assert md =~ "Hello world"
      assert md =~ "Second paragraph"
    end

    test "converts code blocks" do
      html = "<pre><code>def hello, do: :world</code></pre>"
      md = HexDocs.html_to_markdown(html)
      assert md =~ "```"
      assert md =~ "def hello, do: :world"
    end

    test "converts inline code" do
      html = "<p>Use <code>Enum.map/2</code> for this.</p>"
      md = HexDocs.html_to_markdown(html)
      assert md =~ "`Enum.map/2`"
    end

    test "converts bold and italic" do
      html = "<p><strong>bold</strong> and <em>italic</em></p>"
      md = HexDocs.html_to_markdown(html)
      assert md =~ "**bold**"
      assert md =~ "*italic*"
    end

    test "converts links" do
      html = ~s(<p><a href="https://example.com">Example</a></p>)
      md = HexDocs.html_to_markdown(html)
      assert md =~ "[Example](https://example.com)"
    end

    test "converts lists" do
      html = "<ul><li>First</li><li>Second</li></ul>"
      md = HexDocs.html_to_markdown(html)
      assert md =~ "- First"
      assert md =~ "- Second"
    end

    test "strips script and style tags" do
      html = "<p>Content</p><script>alert('xss')</script><style>.foo{}</style>"
      md = HexDocs.html_to_markdown(html)
      assert md =~ "Content"
      refute md =~ "alert"
      refute md =~ ".foo"
    end

    test "converts tables to markdown" do
      html = """
      <table>
        <thead><tr><th>Name</th><th>Value</th></tr></thead>
        <tbody><tr><td>foo</td><td>1</td></tr><tr><td>bar</td><td>2</td></tr></tbody>
      </table>
      """

      md = HexDocs.html_to_markdown(html)
      assert md =~ "| Name | Value |"
      assert md =~ "| --- | --- |"
      assert md =~ "| foo | 1 |"
      assert md =~ "| bar | 2 |"
    end

    test "converts blockquotes" do
      html = "<blockquote><p>Important note</p></blockquote>"
      md = HexDocs.html_to_markdown(html)
      assert md =~ "> Important note"
    end

    test "extracts code language from class" do
      html = ~S[<pre><code class="makeup elixir">IO.puts("hello")</code></pre>]
      md = HexDocs.html_to_markdown(html)
      assert md =~ "```elixir"
    end

    test "strips navigation chrome" do
      html = """
      <div id="content">
        <nav><a href="/">Home</a></nav>
        <p>Actual content</p>
        <footer>Copyright</footer>
      </div>
      """

      md = HexDocs.html_to_markdown(html)
      assert md =~ "Actual content"
      refute md =~ "Home"
      refute md =~ "Copyright"
    end

    test "targets #content area" do
      html = """
      <html>
        <body>
          <nav id="sidebar">Sidebar stuff</nav>
          <div id="content">
            <p>Module documentation</p>
          </div>
        </body>
      </html>
      """

      md = HexDocs.html_to_markdown(html)
      assert md =~ "Module documentation"
      refute md =~ "Sidebar stuff"
    end

    test "handles plain text fallback on parse failure" do
      result = HexDocs.html_to_markdown("")
      assert is_binary(result)
    end
  end
end
