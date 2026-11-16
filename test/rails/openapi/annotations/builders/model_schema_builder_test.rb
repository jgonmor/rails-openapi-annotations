# frozen_string_literal: true

require "test_helper"
require "rails/openapi/annotations/builders/model_schema_builder"

class ModelSchemaBuilderTest < Minitest::Test
  Column = Struct.new(
    :name,
    :type,
    :null,
    :default,
    :limit,
    :default_function,
    :comment
  )

  class FakeType
    def cast(value)
      value
    end
  end

  class FakeModel
    ModelName = Struct.new(:param_key)

    attr_reader :columns

    def initialize(
      columns:,
      validators: {},
      param_key: "resource"
    )
      @columns = columns
      @validators = validators
      @param_key = param_key
    end

    def column_names
      columns.map(&:name)
    end

    def primary_key
      "id"
    end

    def inheritance_column
      "type"
    end

    def model_name
      ModelName.new(@param_key)
    end

    def validators_on(name)
      @validators.fetch(name, [])
    end

    def type_for_attribute(_name)
      FakeType.new
    end
  end

  def setup
    @builder =
      ::Rails::Openapi::Annotations::Builders::ModelSchemaBuilder.new
  end

  def column(
    name,
    type: :string,
    null: true,
    default: nil,
    limit: nil,
    comment: nil
  )
    Column.new(
      name,
      type,
      null,
      default,
      limit,
      nil,
      comment
    )
  end

  def model(columns:, validators: {}, param_key: "resource")
    FakeModel.new(
      columns: columns,
      validators: validators,
      param_key: param_key
    )
  end

  def test_exposed_columns_excludes_sensitive_columns
    resource = model(
      columns: [
        column("id", type: :integer),
        column("name"),
        column("password_digest"),
        column("token_version", type: :integer)
      ]
    )

    result = @builder.exposed_columns(resource)

    assert_equal %w[id name], result.map(&:name)
  end

  def test_writable_columns_excludes_system_and_sensitive_columns
    resource = model(
      columns: [
        column("id", type: :integer),
        column("type"),
        column("name"),
        column("created_at", type: :datetime),
        column("updated_at", type: :datetime),
        column("password_digest"),
        column("token_version")
      ]
    )

    result = @builder.writable_columns(resource)

    assert_equal ["name"], result.map(&:name)
  end

  def test_writable_columns_accepts_field_filter
    resource = model(
      columns: [
        column("id", type: :integer),
        column("name"),
        column("email"),
        column("description", type: :text)
      ]
    )

    result = @builder.writable_columns(
      resource,
      only: %w[email description]
    )

    assert_equal %w[email description], result.map(&:name)
  end

  def test_response_schema_excludes_sensitive_columns
    resource = model(
      columns: [
        column("id", type: :integer),
        column("name"),
        column("password_digest"),
        column("token_version", type: :integer)
      ]
    )

    schema = @builder.response_schema(resource)

    assert_equal "object", schema["type"]
    assert_equal %w[id name], schema["required"]
    assert_equal %w[id name], schema["properties"].keys
    assert_equal true, schema["properties"]["id"]["readOnly"]
  end

  def test_request_schema_builds_nested_resource
    resource = model(
      param_key: "user",
      columns: [
        column("id", type: :integer),
        column("name", null: false),
        column("email", null: false)
      ]
    )

    schema = @builder.request_schema(resource)

    assert_equal ["user"], schema["required"]

    user_schema = schema.dig("properties", "user")

    assert_equal "object", user_schema["type"]
    assert_equal %w[name email], user_schema["required"]
    assert_equal %w[name email], user_schema["properties"].keys
  end

  def test_password_authentication_adds_password_fields
    resource = model(
      param_key: "user",
      columns: [
        column("id", type: :integer),
        column("email", null: false),
        column("password_digest")
      ]
    )

    schema = @builder.request_schema(resource)
    properties = schema.dig("properties", "user", "properties")

    assert_equal "password", properties["password"]["format"]
    assert_equal true, properties["password"]["writeOnly"]

    assert_equal "password", properties["password_confirmation"]["format"]
    assert_includes(
      schema.dig("properties", "user", "required"),
      "password"
    )
  end

  def test_partial_request_does_not_require_fields
    resource = model(
      columns: [
        column("id", type: :integer),
        column("name", null: false),
        column("password_digest")
      ]
    )

    schema = @builder.request_schema(resource, partial: true)
    nested_schema = schema.dig("properties", "resource")

    refute nested_schema.key?("required")
  end

  def test_type_schema_maps_common_types
    assert_equal(
      {"type" => "integer", "format" => "int64"},
      @builder.type_schema(column("id", type: :integer, limit: 8))
    )

    assert_equal(
      {"type" => "string", "format" => "date"},
      @builder.type_schema(column("due_date", type: :date))
    )

    assert_equal(
      {
        "type" => "object",
        "additionalProperties" => true
      },
      @builder.type_schema(column("metadata", type: :jsonb))
    )

    assert_equal(
      {"type" => "string", "format" => "uuid"},
      @builder.type_schema(column("uuid", type: :uuid))
    )
  end

  def test_column_schema_includes_comment_and_nullable
    resource = model(
      columns: [
        column(
          "name",
          null: true,
          comment: "User display name"
        )
      ]
    )

    schema = @builder.column_schema(resource, resource.columns.first)

    assert_equal true, schema["nullable"]
    assert_equal "User display name", schema["description"]
    assert_equal "Example name", schema["example"]
  end

  def test_model_example_excludes_sensitive_columns
    resource = model(
      columns: [
        column("id", type: :integer),
        column("name"),
        column("password_digest"),
        column("token_version", type: :integer)
      ]
    )

    example = @builder.model_example(resource)

    assert_equal %w[id name], example.keys
    refute example.key?("password_digest")
    refute example.key?("token_version")
  end

  def test_default_value_normalizes_big_decimal
    resource = model(
      columns: [
        column(
          "price",
          type: :decimal,
          default: BigDecimal("19.99")
        )
      ]
    )

    value = @builder.default_value(
      resource,
      resource.columns.first
    )

    assert_equal 19.99, value
  end
end
