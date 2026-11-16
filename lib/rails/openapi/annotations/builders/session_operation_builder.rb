# frozen_string_literal: true

class Rails::Openapi::Annotations::Builders::SessionOperationBuilder
  def build_operation(metadata, action, verb, _path = nil, _model = nil)
    operation = {
      "summary" => metadata["summary"],
      "description" => metadata["description"],
      "operationId" => (action == "create") ? "createSession" : "destroySession",
      "tags" => ["Authentication"],
      "responses" => {}
    }

    case [action, verb]
    when ["create", "POST"]
      operation["requestBody"] = {
        "required" => true,
        "content" => {
          "application/json" => {
            "schema" => {
              "type" => "object",
              "required" => %w[email password],
              "properties" => {
                "email" => {
                  "type" => "string",
                  "format" => "email",
                  "example" => "user@example.com"
                },
                "password" => {
                  "type" => "string",
                  "format" => "password",
                  "writeOnly" => true,
                  "example" => "Password123!"
                }
              }
            },
            "example" => {
              "email" => "user@example.com",
              "password" => "Password123!"
            }
          }
        }
      }

      operation["responses"]["200"] = {
        "description" => "Session created successfully",
        "content" => {
          "application/json" => {
            "schema" => {
              "type" => "object",
              "properties" => {
                "data" => {
                  "type" => "object",
                  "properties" => {
                    "id" => {"type" => "integer", "example" => 1},
                    "name" => {"type" => "string", "example" => "Juan"},
                    "email" => {
                      "type" => "string",
                      "format" => "email",
                      "example" => "user@example.com"
                    }
                  }
                },
                "access_token" => {
                  "type" => "string",
                  "example" => "eyJhbGciOiJIUzI1NiJ9..."
                },
                "token_type" => {
                  "type" => "string",
                  "example" => "Bearer"
                },
                "expires_in" => {
                  "type" => "integer",
                  "example" => 3600
                }
              }
            },
            "example" => {
              "data" => {
                "id" => 1,
                "name" => "Juan",
                "email" => "user@example.com"
              },
              "access_token" => "eyJhbGciOiJIUzI1NiJ9...",
              "token_type" => "Bearer",
              "expires_in" => 3600
            }
          }
        }
      }

      operation["responses"]["401"] = {
        "description" => "Invalid email or password",
        "content" => {
          "application/json" => {
            "example" => {
              "error" => "Invalid email or password"
            }
          }
        }
      }
    when ["destroy", "DELETE"]
      operation["security"] = [
        {"bearerAuth" => []}
      ]

      operation["responses"]["204"] = {
        "description" => "Session destroyed successfully"
      }

      operation["responses"]["401"] = {
        "description" => "Missing, invalid or expired JWT"
      }
    end

    operation
  end
end
