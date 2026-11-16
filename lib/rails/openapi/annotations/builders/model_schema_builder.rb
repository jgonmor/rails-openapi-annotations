# frozen_string_literal: true

require "date"
require "bigdecimal"

class Rails::Openapi::Annotations::Builders::ModelSchemaBuilder
  SYSTEM_COLUMNS = %w[created_at updated_at].freeze
  SENSITIVE_COLUMNS = %w[password_digest token_version].freeze

  def exposed_columns(model)
    model.columns.reject do |column|
      SENSITIVE_COLUMNS.include?(column.name)
    end
  end

  def response_schema(model)
    columns = exposed_columns(model)

    {
      "type" => "object",
      "required" => columns.map(&:name),
      "properties" => columns.to_h do |column|
        [
          column.name,
          column_schema(model, column)
        ]
      end
    }
  end

  def request_schema(model, partial: false, fields: nil)
    columns = writable_columns(model, only: fields)

    properties = columns.to_h do |column|
      [
        column.name,
        column_schema(model, column)
      ]
    end

    required = if partial
      []
    else
      columns
        .select { |column| required_input?(model, column) }
        .map(&:name)
    end

    if password_authentication?(model)
      properties["password"] = {
        "type" => "string",
        "format" => "password",
        "writeOnly" => true,
        "minLength" => 8,
        "maxLength" => 72,
        "example" => "Password123!"
      }

      properties["password_confirmation"] = {
        "type" => "string",
        "format" => "password",
        "writeOnly" => true,
        "example" => "Password123!"
      }

      required << "password" unless partial
    end

    nested_schema = {
      "type" => "object",
      "properties" => properties
    }

    nested_schema["required"] = required.uniq unless required.empty?

    root_key = model.model_name.param_key

    {
      "type" => "object",
      "required" => [root_key],
      "properties" => {
        root_key => nested_schema
      }
    }
  end

  def writable_columns(model, only: nil)
    excluded = [
      model.primary_key,
      model.inheritance_column,
      *SYSTEM_COLUMNS,
      *SENSITIVE_COLUMNS
    ]

    columns = model.columns.reject do |column|
      excluded.include?(column.name)
    end

    only ? columns.select { |column| only.include?(column.name) } : columns
  end

  def password_authentication?(model)
    model.column_names.include?("password_digest")
  end

  def required_input?(model, column)
    has_presence_validator = model.validators_on(column.name).any? do |validator|
      validator.is_a?(ActiveRecord::Validations::PresenceValidator)
    end

    has_database_requirement =
      !column.null &&
      column.default.nil? &&
      !has_default_function?(column)

    has_presence_validator || has_database_requirement
  end

  def has_default_function?(column)
    column.respond_to?(:default_function) &&
      !column.default_function.nil?
  end

  def column_schema(model, column)
    schema = type_schema(column)

    schema["nullable"] = true if column.null

    if column.name == model.primary_key ||
        SYSTEM_COLUMNS.include?(column.name)
      schema["readOnly"] = true
    end

    if column.respond_to?(:comment) && column.comment.present?
      schema["description"] = column.comment
    end

    unless column.default.nil?
      schema["default"] = default_value(model, column)
    end

    schema["example"] = example_for(model, column)

    schema
  end

  def type_schema(column)
    case column.type
    when :integer, :primary_key
      schema = {"type" => "integer"}
      schema["format"] = "int64" if column.limit && column.limit >= 8
      schema
    when :float
      {"type" => "number", "format" => "float"}
    when :decimal
      {"type" => "number", "format" => "double"}
    when :boolean
      {"type" => "boolean"}
    when :date
      {"type" => "string", "format" => "date"}
    when :datetime, :timestamp
      {"type" => "string", "format" => "date-time"}
    when :time
      {"type" => "string", "format" => "time"}
    when :json, :jsonb
      {
        "type" => "object",
        "additionalProperties" => true
      }
    when :binary
      {"type" => "string", "format" => "byte"}
    when :uuid
      {"type" => "string", "format" => "uuid"}
    else
      {"type" => "string"}
    end
  end

  def default_value(model, column)
    value = model.type_for_attribute(column.name).cast(column.default)
    normalize_value(value)
  end

  def example_for(model, column)
    return default_value(model, column) unless column.default.nil?

    case column.type
    when :integer, :primary_key
      1
    when :float, :decimal
      19.99
    when :boolean
      false
    when :date
      "2026-12-31"
    when :datetime, :timestamp
      "2026-11-03T10:00:00Z"
    when :time
      "10:00:00"
    when :json, :jsonb
      {}
    when :binary
      "ZXhhbXBsZQ=="
    when :uuid
      "550e8400-e29b-41d4-a716-446655440000"
    when :string, :text
      string_example(column.name)
    else
      "example"
    end
  end

  def string_example(column_name)
    examples = {
      "title" => "Example title",
      "name" => "Example name",
      "description" => "Example description",
      "email" => "example@example.com"
    }

    examples.fetch(column_name, "example_#{column_name}")
  end

  def normalize_value(value)
    case value
    when Date, DateTime, Time
      value.iso8601
    when BigDecimal
      value.to_f
    else
      value
    end
  end

  def model_example(model)
    exposed_columns(model).to_h do |column|
      [
        column.name,
        example_for(model, column)
      ]
    end
  end
end
