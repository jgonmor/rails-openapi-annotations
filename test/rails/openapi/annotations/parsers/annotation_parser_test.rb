# frozen_string_literal: true

require "test_helper"

class AnnotationParserTest < Minitest::Test
  def setup
    @parser =
      ::Rails::Openapi::Annotations::Parsers::AnnotationParser.new
  end

  def test_parse_fields
    raw = 'summary:"List tasks" auth:"true" model:"Task"'

    result = @parser.parse_fields(raw)

    assert_equal(
      {
        "summary" => "List tasks",
        "auth" => "true",
        "model" => "Task"
      },
      result
    )
  end

  def test_next_method_index
    lines = [
      "# @openapi summary:\"List tasks\"",
      "def index",
      "  render json: Task.all",
      "end",
      "def show",
      "  render json: Task.find(params[:id])",
      "end"
    ]

    assert_equal 4, @parser.next_method_index(lines, 2)
  end

  def test_extract_literal_error_annotation
    lines = [
      "# @openapi error",
      'render json: { error: "Invalid email or password" }, status: :unauthorized'
    ]

    errors = @parser.extract_error_annotations(
      lines,
      0,
      lines.length
    )

    assert_equal 1, errors.length

    assert_equal(
      {
        "status" => "401",
        "key" => "error",
        "message" => "Invalid email or password",
        "description" => "Invalid email or password"
      },
      errors.first
    )
  end

  def test_extract_dynamic_error_annotation
    lines = [
      '# @openapi error example:"Name cannot be blank"',
      "render json: { errors: user.errors.full_messages }, status: :unprocessable_entity"
    ]

    errors = @parser.extract_error_annotations(
      lines,
      0,
      lines.length
    )

    assert_equal "422", errors.first["status"]
    assert_equal "errors", errors.first["key"]
    assert_equal "Name cannot be blank", errors.first["message"]
  end

  def test_explicit_status_and_key_override
    lines = [
      '# @openapi error status:"404" key:"error" example:"Group not found"',
      "render json: { errors: group.errors.full_messages }, status: :unprocessable_entity"
    ]

    errors = @parser.extract_error_annotations(
      lines,
      0,
      lines.length
    )

    assert_equal "404", errors.first["status"]
    assert_equal "error", errors.first["key"]
    assert_equal "Group not found", errors.first["message"]
  end
end
