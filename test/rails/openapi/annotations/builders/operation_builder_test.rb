# frozen_string_literal: true

require_relative "../../../../test_helper"

require "active_support/core_ext/string/inflections"
require "active_support/core_ext/object/blank"
require "rails/openapi/annotations/builders/operation_builder"

class OperationBuilderTest < Minitest::Test
  Column = Struct.new(:name, :type, :limit)
  ModelName = Struct.new(:singular, :plural, :human, :param_key)

  class FakeModel
    attr_reader :model_name, :columns, :columns_hash

    def initialize
      @model_name = ModelName.new("widget", "widgets", "Widget", "widget")
      @columns = [
        Column.new("id", :integer, 8),
        Column.new("name", :string, nil)
      ]

      @columns_hash = @columns.to_h do |column|
        [column.name, column]
      end
    end

    def primary_key
      "id"
    end
  end

  class FakeModelSchemaBuilder
    attr_reader :request_schema_calls

    def initialize
      @request_schema_calls = []
    end

    def model_example(_model)
      {
        "id" => 1,
        "name" => "Example widget"
      }
    end

    def response_schema(_model)
      {
        "type" => "object",
        "properties" => {
          "id" => {"type" => "integer"},
          "name" => {"type" => "string"}
        }
      }
    end

    def writable_columns(model, only: nil)
      columns = model.columns.reject { |column| column.name == "id" }

      only ? columns.select { |column| only.include?(column.name) } : columns
    end

    def example_for(_model, column)
      {
        "id" => 1,
        "name" => "Example widget"
      }.fetch(column.name, "example")
    end

    def password_authentication?(_model)
      false
    end

    def request_schema(_model, partial: false, fields: nil)
      @request_schema_calls << {
        partial: partial,
        fields: fields
      }

      {"type" => "object"}
    end

    def type_schema(column)
      {"type" => (column.type == :integer) ? "integer" : "string"}
    end
  end

  def setup
    @model = FakeModel.new
    @model_schema_builder = FakeModelSchemaBuilder.new
    @builder = Rails::Openapi::Annotations::Builders::OperationBuilder.new(
      model_schema_builder: @model_schema_builder,
      security_requirement: [{"bearerAuth" => []}],
      response_wrapper: "data"
    )
  end

  def test_builds_index_operation
    operation = build_operation(action: "index", verb: "GET")

    assert_equal "listWidgets", operation["operationId"]
    assert_equal ["Widgets"], operation["tags"]

    response = operation.dig(
      "responses", "200", "content", "application/json"
    )

    assert_equal "array", response.dig("schema", "properties", "data", "type")
    assert_equal(
      {"data" => [{"id" => 1, "name" => "Example widget"}]},
      response["example"]
    )
  end

  def test_builds_show_operation_with_path_parameter
    operation = build_operation(
      action: "show",
      verb: "GET",
      path: "/api/v1/widgets/{id}"
    )

    assert_equal "getWidget", operation["operationId"]
    assert_equal "Widget found", operation.dig("responses", "200", "description")
    assert operation["responses"].key?("404")

    parameter = operation["parameters"].first

    assert_equal "id", parameter["name"]
    assert_equal "path", parameter["in"]
    assert_equal true, parameter["required"]
    assert_equal({"type" => "integer"}, parameter["schema"])
    assert_equal 1, parameter["example"]
  end

  def test_builds_create_operation_with_selected_request_fields
    operation = build_operation(
      action: "create",
      verb: "POST",
      metadata: {"request_fields" => "name"}
    )

    assert_equal "createWidget", operation["operationId"]
    assert operation.key?("requestBody")
    assert operation["responses"].key?("201")
    assert operation["responses"].key?("422")

    assert_equal(
      [{partial: false, fields: ["name"]}],
      @model_schema_builder.request_schema_calls
    )
  end

  def test_builds_partial_update_operations
    [
      ["PATCH", "updateWidget"],
      ["PUT", "replaceWidget"]
    ].each do |verb, expected_operation_id|
      operation = build_operation(
        action: "update",
        verb: verb,
        path: "/api/v1/widgets/{id}"
      )

      assert_equal expected_operation_id, operation["operationId"]
      assert operation.key?("requestBody")
      assert operation["responses"].key?("200")
      assert operation["responses"].key?("404")
      assert operation["responses"].key?("422")
    end

    assert_equal true, @model_schema_builder.request_schema_calls.last[:partial]
  end

  def test_builds_destroy_operation
    operation = build_operation(
      action: "destroy",
      verb: "DELETE",
      path: "/api/v1/widgets/{id}"
    )

    assert_equal "deleteWidget", operation["operationId"]
    assert_equal(
      "Widget deleted successfully",
      operation.dig("responses", "204", "description")
    )
    assert operation["responses"].key?("404")
  end

  def test_uses_configured_security_requirement
    @builder = Rails::Openapi::Annotations::Builders::OperationBuilder.new(
      model_schema_builder: @model_schema_builder,
      security_requirement: [{"apiKeyAuth" => []}]
    )

    operation = build_operation(
      action: "index",
      verb: "GET",
      metadata: {"auth" => "true"}
    )

    assert_equal [{"apiKeyAuth" => []}], operation["security"]
  end

  def test_raises_error_when_auth_is_required_without_configuration
    @builder = Rails::Openapi::Annotations::Builders::OperationBuilder.new(
      model_schema_builder: @model_schema_builder
    )

    assert_raises(Rails::Openapi::Annotations::Error) do
      build_operation(
        action: "index",
        verb: "GET",
        metadata: {"auth" => "true"}
      )
    end
  end

  def test_adds_bearer_authentication_when_enabled
    operation = build_operation(
      action: "index",
      verb: "GET",
      metadata: {"auth" => "true"}
    )

    assert_equal [{"bearerAuth" => []}], operation["security"]
  end

  def test_does_not_add_authentication_when_disabled
    operation = build_operation(
      action: "index",
      verb: "GET",
      metadata: {"auth" => "false"}
    )

    refute operation.key?("security")
  end

  def test_applies_custom_error_annotations
    operation = build_operation(
      action: "create",
      verb: "POST",
      metadata: {
        "errors" => [
          {
            "status" => "409",
            "key" => "conflict",
            "message" => "Widget already exists",
            "description" => "Conflict"
          }
        ]
      }
    )

    response = operation.dig(
      "responses", "409", "content", "application/json"
    )

    assert_equal "Conflict", operation.dig("responses", "409", "description")
    assert_equal(
      {"conflict" => "Widget already exists"},
      response["example"]
    )
    assert_equal ["conflict"], response.dig("schema", "required")
  end

  def test_builds_unwrapped_collection_response_by_default
    builder = Rails::Openapi::Annotations::Builders::OperationBuilder.new(
      model_schema_builder: @model_schema_builder
    )

    operation = builder.build_operation(
      {},
      "index",
      "GET",
      "/api/v1/widgets",
      @model
    )

    response = operation.dig(
      "responses",
      "200",
      "content",
      "application/json"
    )

    assert_equal "array", response.dig("schema", "type")

    assert_equal(
      [{"id" => 1, "name" => "Example widget"}],
      response["example"]
    )
  end

  private

  def build_operation(
    action:,
    verb:,
    path: "/api/v1/widgets",
    metadata: {}
  )
    @builder.build_operation(metadata, action, verb, path, @model)
  end
end
