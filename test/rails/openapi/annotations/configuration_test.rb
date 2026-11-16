# frozen_string_literal: true

require_relative "../../../test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = Rails::Openapi::Annotations::Configuration.new
  end

  def test_defaults_to_no_security_schemes
    assert_equal({}, @configuration.security_schemes)
  end

  def test_defaults_to_no_security_requirement
    assert_nil @configuration.security_requirement
  end

  def test_defaults_to_no_custom_operation_builders
    assert_equal({}, @configuration.operation_builders)
  end

  def test_registers_custom_operation_builder
    builder = Object.new
    builder.define_singleton_method(:build_operation) { nil }

    @configuration.register_operation_builder("api/v1/sessions", builder)

    assert_same builder, @configuration.operation_builders["api/v1/sessions"]
  end

  def test_rejects_builder_without_build_operation
    assert_raises(ArgumentError) do
      @configuration.register_operation_builder(
        "api/v1/sessions",
        Object.new
      )
    end
  end

  def test_defaults_to_no_response_overrides
    assert_equal({}, @configuration.response_overrides)
  end

  def test_allows_custom_response_overrides
    responses = {
      "api/v1/widgets#index" => {
        "200" => {
          "description" => "Custom widget response"
        }
      }
    }

    @configuration.response_overrides = responses

    assert_equal responses, @configuration.response_overrides
  end

  def test_defaults_to_no_schemas
    assert_equal({}, @configuration.schemas)
  end

  def test_allows_custom_schemas
    schemas = {
      "Widget" => {
        "type" => "object",
        "properties" => {
          "id" => {"type" => "integer"},
          "name" => {"type" => "string"}
        }
      }
    }

    @configuration.schemas = schemas

    assert_equal schemas, @configuration.schemas
  end

  def test_defaults_to_no_request_body_overrides
    assert_equal({}, @configuration.request_body_overrides)
  end

  def test_allows_custom_request_body_overrides
    overrides = {
      "api/v1/widgets#create" => {
        "required" => true,
        "content" => {
          "application/json" => {
            "schema" => {
              "$ref" => "#/components/schemas/CreateWidget"
            }
          }
        }
      }
    }

    @configuration.request_body_overrides = overrides

    assert_equal overrides, @configuration.request_body_overrides
  end

  def test_defaults_to_no_response_wrapper
    assert_nil @configuration.response_wrapper
  end

  def test_allows_custom_response_wrapper
    @configuration.response_wrapper = "data"

    assert_equal "data", @configuration.response_wrapper
  end
end
