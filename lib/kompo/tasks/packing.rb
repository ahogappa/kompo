# frozen_string_literal: true

require_relative "../cache/packing"
require_relative "packing/common_helpers"

module Kompo
  # Task to compile the final binary.
  # Switches implementation based on the current platform.
  # Uses CollectDependencies's exported values for dependencies.
  class Packing < Taski::Task
    autoload :ForMacOS, "kompo/tasks/packing/macos"
    autoload :ForLinux, "kompo/tasks/packing/linux"

    exports :output_path

    def run
      @output_path = if Kompo.macos?
        ForMacOS.output_path
      else
        ForLinux.output_path
      end
    end
  end
end
