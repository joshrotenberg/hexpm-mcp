defmodule HexpmMcp.FormatterTest do
  use ExUnit.Case, async: true

  alias HexpmMcp.Formatter

  describe "format_number/1" do
    test "formats millions" do
      assert Formatter.format_number(1_234_567) == "1.2M"
      assert Formatter.format_number(5_000_000) == "5.0M"
    end

    test "formats thousands" do
      assert Formatter.format_number(45_678) == "45.7K"
      assert Formatter.format_number(1_000) == "1.0K"
    end

    test "formats small numbers" do
      assert Formatter.format_number(999) == "999"
      assert Formatter.format_number(0) == "0"
    end

    test "formats nil" do
      assert Formatter.format_number(nil) == "0"
    end
  end

  describe "format_date/1" do
    test "extracts date from ISO string" do
      assert Formatter.format_date("2024-01-15T12:30:00Z") == "2024-01-15"
    end

    test "handles nil" do
      assert Formatter.format_date(nil) == "unknown"
    end
  end

  describe "markdown_table/2" do
    test "builds a markdown table" do
      headers = ["Name", "Value"]
      rows = [["foo", "1"], ["bar", "2"]]

      result = Formatter.markdown_table(headers, rows)
      assert result =~ "| Name"
      assert result =~ "| foo"
      assert result =~ "| bar"
    end
  end
end
