# frozen_string_literal: true

require_relative "../../../test_helper"

require "tmpdir"
require "pathname"
require "yaml"
require "rails/openapi/annotations/generator"

class GeneratorTest < Minitest::Test
  FakeRoute = Struct.new(:defaults, :path, :verb)
  FakePath = Struct.new(:spec)
  FakeRoutes = Struct.new(:routes)
  FakeApplication = Struct.new(:routes, :root)

  class FakeScanner
    def initialize(annotations)
      @annotations = annotations
    end

    def scan
      @annotations
    end
  end

  class RecordingBuilder
    attr_reader :calls

    def initialize
      @calls = []
    end

    def build_operation(metadata, action, verb, path, model)
      @calls << {
        metadata: metadata,
        action: action,
        verb: verb,
        path: path,
        model: model
      }

      {
        "summary" => metadata["summary"],
        "operationId" => "customOperation",
        "responses" => {
          "200" => {
            "description" => "OK"
          }
        }
      }
    end
  end

  def setup
    @tmpdir = Dir.mktmpdir

    configure_generation(
      controller: "api/v1/widgets",
      action: "index",
      verb: "GET",
      path: "/api/v1/widgets",
      metadata: {"summary" => "List widgets"}
    )
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if File.exist?(@tmpdir)
  end

  def test_generates_document_without_security_by_default
    document = generate_document

    operation = document.dig(
      "paths",
      "/api/v1/widgets",
      "get"
    )

    refute document.key?("components")
    refute operation.key?("security")
    refute File.read(output_path).include?("bearerAuth")
  end

  def test_includes_configured_security_schemes
    @configuration.security_schemes = {
      "apiKeyAuth" => {
        "type" => "apiKey",
        "in" => "header",
        "name" => "X-API-Key"
      }
    }

    document = generate_document

    assert_equal(
      {
        "securitySchemes" => @configuration.security_schemes
      },
      document["components"]
    )
  end

  def test_uses_registered_builder_for_sessions_controller
    metadata = {"summary" => "Create session"}

    configure_generation(
      controller: "api/v1/sessions",
      action: "create",
      verb: "POST",
      path: "/api/v1/sessions",
      metadata: metadata
    )

    document = generate_document

    assert_equal 1, @builder.calls.length

    call = @builder.calls.first

    assert_equal "create", call[:action]
    assert_equal "POST", call[:verb]
    assert_equal "/api/v1/sessions", call[:path]
    assert_nil call[:model]

    assert document.dig(
      "paths",
      "/api/v1/sessions",
      "post"
    )
  end

  def test_applies_configured_response_overrides
    @configuration.response_overrides = {
      "api/v1/widgets#index" => {
        "200" => {
          "description" => "Custom widgets response"
        },
        "401" => {
          "description" => "Unauthorized"
        }
      }
    }

    document = generate_document

    operation = document.dig(
      "paths",
      "/api/v1/widgets",
      "get"
    )

    assert_equal(
      "Custom widgets response",
      operation.dig("responses", "200", "description")
    )

    assert_equal(
      "Unauthorized",
      operation.dig("responses", "401", "description")
    )
  end

  def test_includes_custom_schemas_and_response_references
    widget_schema = {
      "type" => "object",
      "properties" => {
        "id" => {"type" => "integer"},
        "name" => {"type" => "string"}
      },
      "required" => ["id", "name"]
    }

    @configuration.schemas = {
      "Widget" => widget_schema
    }

    @configuration.security_schemes = {
      "apiKeyAuth" => {
        "type" => "apiKey",
        "in" => "header",
        "name" => "X-API-Key"
      }
    }

    @configuration.response_overrides = {
      "api/v1/widgets#index" => {
        "200" => {
          "description" => "Widgets retrieved successfully",
          "content" => {
            "application/json" => {
              "schema" => {
                "$ref" => "#/components/schemas/Widget"
              }
            }
          }
        }
      }
    }

    document = generate_document

    assert_equal(
      widget_schema,
      document.dig("components", "schemas", "Widget")
    )

    assert_equal(
      @configuration.security_schemes,
      document.dig("components", "securitySchemes")
    )

    assert_equal(
      "#/components/schemas/Widget",
      document.dig(
        "paths",
        "/api/v1/widgets",
        "get",
        "responses",
        "200",
        "content",
        "application/json",
        "schema",
        "$ref"
      )
    )
  end

  def test_applies_configured_request_body_overrides
    configure_generation(
      controller: "api/v1/inventory_items",
      action: "create",
      verb: "POST",
      path: "/api/v1/inventory_items",
      metadata: {"summary" => "Create inventory item"}
    )

    request_body = {
      "required" => true,
      "content" => {
        "application/json" => {
          "schema" => {
            "$ref" => "#/components/schemas/CreateInventoryItem"
          }
        }
      }
    }

    @configuration.schemas = {
      "CreateInventoryItem" => {
        "type" => "object",
        "properties" => {
          "name" => {"type" => "string"}
        },
        "required" => ["name"]
      }
    }

    @configuration.request_body_overrides = {
      "api/v1/inventory_items#create" => request_body
    }

    document = generate_document

    operation = document.dig(
      "paths",
      "/api/v1/inventory_items",
      "post"
    )

    assert_equal request_body, operation["requestBody"]

    assert_equal(
      "#/components/schemas/CreateInventoryItem",
      operation.dig(
        "requestBody",
        "content",
        "application/json",
        "schema",
        "$ref"
      )
    )
  end

  private

  def configure_generation(controller:, action:, verb:, path:, metadata:)
    @annotations = {
      controller => {
        action => metadata
      }
    }

    @builder = RecordingBuilder.new
    @configuration = Rails::Openapi::Annotations::Configuration.new

    @configuration.register_operation_builder(
      controller,
      @builder
    )

    route = FakeRoute.new(
      {
        controller: controller,
        action: action
      },
      FakePath.new("#{path}(.:format)"),
      verb
    )

    routes = FakeRoutes.new([route])

    @application = FakeApplication.new(
      routes,
      Pathname.new(@tmpdir)
    )

    @generator = Rails::Openapi::Annotations::Generator.new(
      application: @application,
      configuration: @configuration,
      controller_scanner: FakeScanner.new(@annotations)
    )
  end

  def generate_document
    output = @generator.generate!

    YAML.safe_load_file(output)
  end

  def output_path
    File.join(@tmpdir, "openapi", "openapi.yaml")
  end
end
