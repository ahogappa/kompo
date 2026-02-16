# frozen_string_literal: true

require_relative "test_helper"

class ConfigureProgressTest < Minitest::Test
  def teardown
    Taski.reset_progress_display!
  end

  def test_log_mode_sets_log_layout
    Kompo.configure_progress("log")
    assert_equal Taski::Progress::Layout::Log, Taski.progress.layout
  end

  def test_tree_mode_sets_tree_layout
    Kompo.configure_progress("tree")
    assert_equal Taski::Progress::Layout::Tree, Taski.progress.layout
  end

  def test_none_mode_disables_progress
    Kompo.configure_progress("none")
    assert_nil Taski.progress_display
  end

  def test_simple_mode_is_default
    Kompo.configure_progress("simple")
    assert_nil Taski.progress.layout
  end

  def test_nil_does_nothing
    Kompo.configure_progress(nil)
    assert_nil Taski.progress.layout
  end

  def test_unknown_mode_raises_error
    assert_raises(ArgumentError) do
      Kompo.configure_progress("unknown")
    end
  end
end
