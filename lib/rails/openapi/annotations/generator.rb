# frozen_string_literal: true

require_relative "parsers/controller_scanner"
require_relative "builders/model_schema_builder"
require_relative "builders/operation_builder"
require "yaml"
require "json"
require "fileutils"
require "pathname"
require "date"
require "bigdecimal"

class Rails::Openapi::Annotations::Generator
  HTTP_VERBS = %w[GET POST PUT PATCH DELETE].freeze

  SYSTEM_COLUMNS = %w[
    created_at
    updated_at
  ].freeze

  SENSITIVE_COLUMNS = %w[
    password_digest
    token_version
  ].freeze

  def initialize(
    application: Rails.application,
    configuration: ::Rails::Openapi::Annotations.configuration,
    controller_scanner: nil
  )
    @application = application
    @configuration = configuration
    @controller_scanner = controller_scanner

    @model_schema_builder =
      ::Rails::Openapi::Annotations::Builders::ModelSchemaBuilder.new

    @operation_builder =
      ::Rails::Openapi::Annotations::Builders::OperationBuilder.new(
        model_schema_builder: @model_schema_builder,
        security_requirement: @configuration.security_requirement,
        response_wrapper: @configuration.response_wrapper
      )
  end

  def generate!
    scanner = @controller_scanner ||
      ::Rails::Openapi::Annotations::Parsers::ControllerScanner.new(@application)

    annotations = scanner.scan
    paths = {}
    models = {}

    # Discover registered Rails routes.
    @application.routes.routes.each do |route|
      controller = route.defaults[:controller].to_s
      action = route.defaults[:action].to_s

      metadata = annotations.dig(controller, action)
      next unless metadata

      custom_builder = @configuration.operation_builders[controller]

      model = if custom_builder
        nil
      elsif metadata["model"].present?
        model_class = metadata["model"].safe_constantize

        unless model_class && model_class < ActiveRecord::Base
          raise "Invalid model '#{metadata["model"]}' in #{controller}"
        end

        model_class
      else
        models[controller] ||= infer_model(controller)
      end

      path = route.path.spec.to_s
        .sub(/\(\.:format\)\z/, "")
        .gsub(/:([a-zA-Z_]\w*)/) { "{#{$1}}" }

      verbs_for(route).each do |verb|
        paths[path] ||= {}

        operation = if custom_builder
          custom_builder.build_operation(metadata, action, verb, path, model)
        else
          @operation_builder.build_operation(metadata, action, verb, path, model)
        end

        operation = apply_response_overrides(
          operation,
          controller,
          action
        )

        operation = apply_request_body_overrides(
          operation,
          controller,
          action
        )

        paths[path][verb.downcase] = operation
      end
    end

    raise "No annotated operations found in Rails routes" if paths.empty?

    document = {
      "openapi" => "3.0.3",
      "info" => {
        "title" => ENV.fetch("OPENAPI_TITLE", "Rails API"),
        "version" => ENV.fetch("OPENAPI_VERSION", "1.0.0"),
        "description" => "Generated from Rails controller annotations"
      },
      "servers" => [
        {
          "url" => ENV.fetch(
            "OPENAPI_SERVER_URL",
            "http://localhost:3000"
          )
        }
      ],
      "paths" => paths.sort.to_h
    }

    output = @application.root.join("openapi", "openapi.yaml")

    FileUtils.mkdir_p(output.dirname)

    components = {}

    unless @configuration.security_schemes.empty?
      components["securitySchemes"] = @configuration.security_schemes
    end

    unless @configuration.schemas.empty?
      components["schemas"] = @configuration.schemas
    end

    document["components"] = components unless components.empty?

    # Avoid YAML aliases that Rswag's safe_load rejects.
    yaml_document = JSON.parse(JSON.generate(document))

    File.write(output, YAML.dump(yaml_document))

    puts "OpenAPI generated: #{output}"
    puts "Paths: #{paths.length}"
    puts "Operations: #{paths.values.sum(&:length)}"

    output
  end

  private

  # --------------------------------------------------
  # ActiveRecord model discovery
  # --------------------------------------------------

  def infer_model(controller)
    resource = controller.split("/").last
    model_name = resource.singularize.camelize
    model = model_name.safe_constantize

    unless model && model < ActiveRecord::Base
      raise <<~MESSAGE
        Could not infer an ActiveRecord model for #{controller}.
        Expected a model named #{model_name}.
        A custom model mapping can be added in a future version.
      MESSAGE
    end

    model
  end

  # --------------------------------------------------
  # OpenAPI responses and examples
  # --------------------------------------------------

  def verbs_for(route)
    source = if route.verb.respond_to?(:source)
      route.verb.source
    else
      route.verb.to_s
    end

    source.scan(/\b(?:GET|POST|PUT|PATCH|DELETE)\b/).uniq & HTTP_VERBS
  end

  def apply_response_overrides(operation, controller, action)
    key = "#{controller}##{action}"
    overrides = @configuration.response_overrides[key]

    return operation if overrides.nil? || overrides.empty?

    operation["responses"] = operation.fetch("responses", {}).merge(overrides)

    operation
  end

  def apply_request_body_overrides(operation, controller, action)
    key = "#{controller}##{action}"
    override = @configuration.request_body_overrides[key]

    return operation if override.nil?

    operation["requestBody"] = override

    operation
  end
end
