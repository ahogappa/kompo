# frozen_string_literal: true

require "erb"
require "fileutils"

module Kompo
  # Generate main.c from ERB template
  # Required context:
  #   - exts: Array of [so_path, init_func] pairs from native gem builds
  # Dependencies provide:
  #   - WorkDir.path
  #   - CopyProjectFiles.entrypoint_path
  class MakeMainC < Taski::Task
    exports :path

    def run
      work_dir = WorkDir.path
      @path = File.join(work_dir, "main.c")

      return if File.exist?(@path)

      template_path = File.join(__dir__, "..", "..", "main.c.erb")
      template = ERB.new(File.read(template_path))

      # Build context object for ERB template
      context = build_template_context

      File.write(@path, template.result(binding))
      puts "Generated: main.c"
    end

    def clean
      return unless @path && File.exist?(@path)

      FileUtils.rm_f(@path)
      puts "Cleaned up main.c"
    end

    private

    CONTROL_CHAR_MAP = {"\n" => "\\n", "\r" => "\\r", "\t" => "\\t"}.freeze
    private_constant :CONTROL_CHAR_MAP

    def c_string_escape(str)
      str.delete("\0")
        .gsub("\\") { "\\\\" }
        .gsub('"') { '\\"' }
        .gsub(/[\x01-\x1f\x7f]/) { |c| CONTROL_CHAR_MAP[c] || format("\\x%02x", c.ord) }
    end

    def build_template_context
      project_dir = Taski.args.fetch(:project_dir, Taski.env.working_directory) || Taski.env.working_directory
      work_dir = WorkDir.path
      entrypoint = CopyProjectFiles.entrypoint_path

      raw_exts = BuildNativeGem.exts || []
      escaped_exts = raw_exts.map { |ext_path, func| [c_string_escape(ext_path), func] }

      TemplateContext.new(
        exts: escaped_exts,
        work_dir: work_dir,
        work_dir_entrypoint: c_string_escape(entrypoint),
        project_dir: c_string_escape(project_dir),
        has_gemfile: CopyGemfile.gemfile_exists
      )
    end

    # Simple struct to hold template variables
    TemplateContext = Struct.new(
      :exts,
      :work_dir,
      :work_dir_entrypoint,
      :project_dir,
      :has_gemfile,
      keyword_init: true
    )
  end
end
