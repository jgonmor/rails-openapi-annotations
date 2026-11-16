# frozen_string_literal: true

require "pathname"
require_relative "annotation_parser"

class Rails::Openapi::Annotations::Parsers::ControllerScanner
  def initialize(application, parser: ::Rails::Openapi::Annotations::Parsers::AnnotationParser.new)
    @application = application
    @parser = parser
  end

  def scan
    root = @application.root.join("app/controllers")
    annotations = {}

    Dir.glob(root.join("**/*_controller.rb")).sort.each do |file|
      relative_path = Pathname.new(file)
        .relative_path_from(root)
        .to_s
        .sub(/\.rb\z/, "")
        .sub(/_controller\z/, "")

      lines = File.readlines(file)
      annotations[relative_path] ||= {}

      lines.each_with_index do |line, index|
        match = line.match(
          /^\s*#\s*@openapi\s+(.+?)\s*$/
        )

        next unless match

        raw_annotation = match[1].strip

        # Error annotations are associated with render statements,
        # not with controller actions.
        next if raw_annotation.match?(/\Aerror(?:\s|\z)/)

        fields = @parser.parse_fields(raw_annotation)

        method_index = index + 1

        while method_index < lines.length &&
            lines[method_index].strip.empty?
          method_index += 1
        end

        method_match = lines[method_index]&.match(
          /^\s*def\s+([a-zA-Z_]\w*[!?=]?)/
        )

        unless method_match
          raise "Could not find action after @openapi in #{file}:#{index + 1}"
        end

        method_end = @parser.next_method_index(
          lines,
          method_index + 1
        )

        fields["errors"] = @parser.extract_error_annotations(
          lines,
          method_index + 1,
          method_end
        )

        annotations[relative_path][method_match[1]] = fields
      end
    end

    annotations
  end
end
