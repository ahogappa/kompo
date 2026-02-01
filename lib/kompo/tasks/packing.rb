# frozen_string_literal: true

require_relative "../cache/packing"
require_relative "packing/common_helpers"
require_relative "packing/macos"
require_relative "packing/linux"

module Kompo
  # Section to compile the final binary.
  # Switches implementation based on the current platform.
  # Uses CollectDependencies's exported values for dependencies.
  class Packing < Taski::Section
    interfaces :output_path

    def impl
      Kompo.macos? ? ForMacOS : ForLinux
    end
  end
end
