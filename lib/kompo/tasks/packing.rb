# frozen_string_literal: true

require_relative "../cache/packing"
require_relative "packing/common_helpers"

module Kompo
  # Section to compile the final binary.
  # Switches implementation based on the current platform.
  # Uses CollectDependencies's exported values for dependencies.
  class Packing < Taski::Section
    autoload :ForMacOS, "kompo/tasks/packing/macos"
    autoload :ForLinux, "kompo/tasks/packing/linux"

    interfaces :output_path

    def impl
      Kompo.macos? ? ForMacOS : ForLinux
    end
  end
end
