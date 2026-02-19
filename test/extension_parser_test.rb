# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/kompo/extension_parser"

class ExtensionParserTest < Minitest::Test
  def test_parse_cargo_toml_target_name_prefers_lib_name
    content = <<~TOML
      [package]
      name = "package_name"
      version = "0.1.0"

      [lib]
      name = "lib_name"
      crate-type = ["staticlib"]
    TOML

    result = Kompo::ExtensionParser.parse_cargo_toml_target_name(content)

    assert_equal "lib_name", result
  end

  def test_parse_cargo_toml_target_name_falls_back_to_package_name
    content = <<~TOML
      [package]
      name = "package_name"
      version = "0.1.0"
    TOML

    result = Kompo::ExtensionParser.parse_cargo_toml_target_name(content)

    assert_equal "package_name", result
  end

  def test_parse_cargo_toml_target_name_returns_nil_when_no_name
    content = <<~TOML
      [dependencies]
      some_crate = "1.0"
    TOML

    result = Kompo::ExtensionParser.parse_cargo_toml_target_name(content)

    assert_nil result
  end

  def test_parse_cargo_toml_target_name_handles_single_quotes
    content = <<~TOML
      [package]
      name = 'single_quoted_name'
    TOML

    result = Kompo::ExtensionParser.parse_cargo_toml_target_name(content)

    assert_equal "single_quoted_name", result
  end

  def test_parse_cargo_toml_target_name_handles_spaces_around_equals
    content = <<~TOML
      [package]
      name   =   "spaced_name"
    TOML

    result = Kompo::ExtensionParser.parse_cargo_toml_target_name(content)

    assert_equal "spaced_name", result
  end

  def test_parse_cargo_toml_target_name_ignores_name_in_other_sections
    content = <<~TOML
      [dependencies]
      name = "should_be_ignored"

      [package]
      name = "package_name"
    TOML

    result = Kompo::ExtensionParser.parse_cargo_toml_target_name(content)

    assert_equal "package_name", result
  end

  def test_parse_makefile_metadata_extracts_target_name
    content = <<~MAKEFILE
      TARGET_NAME = bigdecimal
      target_prefix =
      OBJS = bigdecimal.o missing.o
    MAKEFILE

    prefix, target_name = Kompo::ExtensionParser.parse_makefile_metadata(content, "fallback")

    assert_equal "", prefix
    assert_equal "bigdecimal", target_name
  end

  def test_parse_makefile_metadata_extracts_prefix
    content = <<~MAKEFILE
      TARGET_NAME = escape
      target_prefix = /cgi
      OBJS = escape.o
    MAKEFILE

    prefix, target_name = Kompo::ExtensionParser.parse_makefile_metadata(content, "fallback")

    assert_equal "cgi", prefix
    assert_equal "escape", target_name
  end

  def test_parse_makefile_metadata_uses_fallback_when_no_target_name
    content = <<~MAKEFILE
      target_prefix = /erb
      OBJS = escape.o
    MAKEFILE

    prefix, target_name = Kompo::ExtensionParser.parse_makefile_metadata(content, "my_fallback")

    assert_equal "erb", prefix
    assert_equal "my_fallback", target_name
  end

  def test_parse_makefile_metadata_returns_empty_prefix_when_not_found
    content = <<~MAKEFILE
      TARGET_NAME = simple
      OBJS = simple.o
    MAKEFILE

    prefix, target_name = Kompo::ExtensionParser.parse_makefile_metadata(content, "fallback")

    assert_equal "", prefix
    assert_equal "simple", target_name
  end

  def test_parse_makefile_metadata_strips_leading_slash_from_prefix
    content = <<~MAKEFILE
      TARGET_NAME = parser
      target_prefix = /racc
      OBJS = parser.o
    MAKEFILE

    prefix, target_name = Kompo::ExtensionParser.parse_makefile_metadata(content, "fallback")

    assert_equal "racc", prefix
    assert_equal "parser", target_name
  end

  def test_parse_makefile_metadata_handles_empty_prefix
    content = <<~MAKEFILE
      TARGET_NAME = nokogiri
      target_prefix =
      OBJS = nokogiri.o
    MAKEFILE

    prefix, target_name = Kompo::ExtensionParser.parse_makefile_metadata(content, "fallback")

    assert_equal "", prefix
    assert_equal "nokogiri", target_name
  end

  def test_parse_makefile_metadata_rejects_invalid_target_name
    content = <<~MAKEFILE
      TARGET_NAME = evil;system("rm")
      target_prefix =
    MAKEFILE

    assert_raises(Kompo::ExtensionParser::ValidationError) do
      Kompo::ExtensionParser.parse_makefile_metadata(content, "fallback")
    end
  end

  def test_parse_makefile_metadata_rejects_invalid_prefix
    content = <<~MAKEFILE
      TARGET_NAME = valid
      target_prefix = /../../etc
    MAKEFILE

    assert_raises(Kompo::ExtensionParser::ValidationError) do
      Kompo::ExtensionParser.parse_makefile_metadata(content, "fallback")
    end
  end

  def test_parse_cargo_toml_target_name_rejects_invalid_name
    content = <<~TOML
      [lib]
      name = "evil;hack"
    TOML

    assert_raises(Kompo::ExtensionParser::ValidationError) do
      Kompo::ExtensionParser.parse_cargo_toml_target_name(content)
    end
  end

  def test_parse_makefile_metadata_accepts_nested_prefix
    content = <<~MAKEFILE
      TARGET_NAME = parser
      target_prefix = /json/ext
    MAKEFILE

    prefix, target_name = Kompo::ExtensionParser.parse_makefile_metadata(content, "fallback")

    assert_equal "json/ext", prefix
    assert_equal "parser", target_name
  end

  def test_parse_cargo_toml_target_name_accepts_hyphenated_name
    content = <<~TOML
      [lib]
      name = "my-crate-name"
    TOML

    result = Kompo::ExtensionParser.parse_cargo_toml_target_name(content)

    assert_equal "my-crate-name", result
  end

  def test_parse_makefile_metadata_uses_fallback_when_target_name_is_empty
    # Trailing space after = so regex matches but captures empty string
    content = "TARGET_NAME = \ntarget_prefix =\n"

    prefix, target_name = Kompo::ExtensionParser.parse_makefile_metadata(content, "my_fallback")

    assert_equal "", prefix
    assert_equal "my_fallback", target_name
  end

  def test_parse_cargo_toml_falls_back_to_package_when_lib_name_is_whitespace
    content = <<~TOML
      [lib]
      name = "   "

      [package]
      name = "real_package"
    TOML

    result = Kompo::ExtensionParser.parse_cargo_toml_target_name(content)

    assert_equal "real_package", result
  end

  def test_parse_makefile_metadata_collapses_consecutive_slashes_in_prefix
    content = <<~MAKEFILE
      TARGET_NAME = parser
      target_prefix = ///json//ext
    MAKEFILE

    prefix, target_name = Kompo::ExtensionParser.parse_makefile_metadata(content, "fallback")

    assert_equal "json/ext", prefix
    assert_equal "parser", target_name
  end
end
