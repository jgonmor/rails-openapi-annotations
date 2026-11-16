# frozen_string_literal: true

class Rails::Openapi::Annotations::Builders::OperationBuilder
  def initialize(model_schema_builder:, security_requirement: nil, response_wrapper: nil)
    @model_schema_builder = model_schema_builder
    @security_requirement = security_requirement
    @response_wrapper = response_wrapper
  end

  def build_operation(metadata, action, verb, path, model)
    singular = model.model_name.singular.camelize
    plural = model.model_name.plural.camelize
    resource_name = model.model_name.human
    collection_name = model.model_name.plural.humanize

    operation_id = {
      ["index", "GET"] => "list#{plural}",
      ["show", "GET"] => "get#{singular}",
      ["create", "POST"] => "create#{singular}",
      ["update", "PATCH"] => "update#{singular}",
      ["update", "PUT"] => "replace#{singular}",
      ["destroy", "DELETE"] => "delete#{singular}"
    }[[action, verb]] || "#{action}#{singular}"

    operation = {
      "summary" => metadata["summary"],
      "description" => metadata["description"],
      "operationId" => operation_id,
      "tags" => [plural],
      "responses" => {}
    }

    if metadata["auth"] == "true"
      if @security_requirement.nil? || @security_requirement.empty?
        raise ::Rails::Openapi::Annotations::Error,
          "Operation requires authentication but no security_requirement is configured"
      end

      operation["security"] = @security_requirement
    end

    parameters = path_parameters(path, model)
    operation["parameters"] = parameters unless parameters.empty?

    example = @model_schema_builder.model_example(model)
    item_schema = @model_schema_builder.response_schema(model)

    case [action, verb]
    when ["index", "GET"]
      schema, response_example = wrap_response(
        {
          "type" => "array",
          "items" => item_schema
        },
        [example]
      )

      operation["responses"]["200"] = json_response(
        "#{collection_name} retrieved successfully",
        schema,
        response_example
      )
    when ["show", "GET"]
      schema, response_example = wrap_response(item_schema, example)

      operation["responses"]["200"] = json_response(
        "#{resource_name} found",
        schema,
        response_example
      )

      operation["responses"]["404"] = not_found_response(model)
    when ["create", "POST"]
      operation["requestBody"] = request_body(
        model,
        fields: request_fields(metadata)
      )

      operation["responses"]["201"] = json_response(
        "#{resource_name} created",
        *wrap_response(item_schema, example)
      )

      operation["responses"]["422"] = validation_response(model)
    when ["update", "PATCH"], ["update", "PUT"]
      operation["requestBody"] = request_body(
        model,
        partial: true,
        fields: request_fields(metadata)
      )

      operation["responses"]["200"] = json_response(
        "#{resource_name} updated",
        *wrap_response(item_schema, example)
      )

      operation["responses"]["404"] = not_found_response(model)
      operation["responses"]["422"] = validation_response(model)
    when ["destroy", "DELETE"]
      operation["responses"]["204"] = {
        "description" => "#{resource_name} deleted successfully"
      }

      operation["responses"]["404"] = not_found_response(model)
    end

    apply_error_annotations(
      operation,
      metadata["errors"] || []
    )

    operation
  end

  private

  def json_response(description, schema, example)
    {
      "description" => description,
      "content" => {
        "application/json" => {
          "schema" => schema,
          "example" => example
        }
      }
    }
  end

  def not_found_response(model)
    resource_name = model.model_name.human
    message = "#{resource_name} not found"

    json_response(
      message,
      {
        "type" => "object",
        "required" => ["error"],
        "properties" => {
          "error" => {"type" => "string"}
        }
      },
      {"error" => message}
    )
  end

  def validation_response(model)
    resource_name = model.model_name.human
    message = "#{resource_name} is invalid"

    json_response(
      "#{resource_name} validation error",
      {
        "type" => "object",
        "required" => ["errors"],
        "properties" => {
          "errors" => {
            "type" => "array",
            "items" => {"type" => "string"}
          }
        }
      },
      {"errors" => [message]}
    )
  end

  def request_body(model, partial: false, fields: nil)
    root_key = model.model_name.param_key

    example = @model_schema_builder.writable_columns(
      model,
      only: fields
    ).to_h do |column|
      [
        column.name,
        @model_schema_builder.example_for(model, column)
      ]
    end

    if @model_schema_builder.password_authentication?(model)
      example["password"] = "Password123!"
      example["password_confirmation"] = "Password123!"
    end

    {
      "required" => true,
      "content" => {
        "application/json" => {
          "schema" => @model_schema_builder.request_schema(
            model,
            partial: partial,
            fields: fields
          ),
          "example" => {
            root_key => example
          }
        }
      }
    }
  end

  def path_parameters(path, model)
    path.scan(/\{([^}]+)\}/).flatten.map do |name|
      column = if name == "id"
        model.columns_hash[model.primary_key]
      else
        model.columns_hash[name]
      end

      parameter = {
        "name" => name,
        "in" => "path",
        "required" => true,
        "description" => "#{name.capitalize} identifier",
        "schema" => column ? @model_schema_builder.type_schema(column) : {"type" => "string"},
        "example" => column ? @model_schema_builder.example_for(model, column) : "example"
      }

      parameter
    end
  end

  def request_fields(metadata)
    metadata["request_fields"]
      &.split(",")
      &.map(&:strip)
      &.reject(&:blank?)
  end

  def apply_error_annotations(operation, errors)
    errors.each do |error|
      status = error.fetch("status")
      key = error.fetch("key")
      message = error.fetch("message")

      schema = if key == "errors"
        {
          "type" => "object",
          "required" => ["errors"],
          "properties" => {
            "errors" => {
              "type" => "array",
              "items" => {
                "type" => "string"
              }
            }
          }
        }
      else
        {
          "type" => "object",
          "required" => [key],
          "properties" => {
            key => {
              "type" => "string"
            }
          }
        }
      end

      example = if key == "errors"
        {"errors" => [message]}
      else
        {key => message}
      end

      operation["responses"][status] = {
        "description" => error["description"],
        "content" => {
          "application/json" => {
            "schema" => schema,
            "example" => example
          }
        }
      }
    end
  end

  def wrap_response(schema, example)
    return [schema, example] if @response_wrapper.nil? ||
      @response_wrapper.empty?

    wrapped_schema = {
      "type" => "object",
      "required" => [@response_wrapper],
      "properties" => {
        @response_wrapper => schema
      }
    }

    wrapped_example = {
      @response_wrapper => example
    }

    [wrapped_schema, wrapped_example]
  end
end
