# frozen_string_literal: true

class Rails::Openapi::Annotations::Parsers::AnnotationParser
  def parse_fields(raw)
    raw.to_s.scan(
      /([a-zA-Z_]\w*)\s*:\s*"((?:\\.|[^"])*)"/
    ).to_h
  end

  def next_method_index(lines, start_index)
    (start_index...lines.length).find do |index|
      lines[index].match?(/^\s*def\s+[a-zA-Z_]/)
    end || lines.length
  end

  def extract_error_annotations(lines, start_index, end_index)
    errors = []

    (start_index...end_index).each do |index|
      marker = lines[index].match(
        /^\s*#\s*@openapi\s+error(?:\s+(.*))?\s*$/
      )

      next unless marker

      options = parse_fields(marker[1])

      search_end = [index + 21, end_index].min

      render_index = ((index + 1)...search_end).find do |i|
        lines[i].match?(/render\s+json:/)
      end

      unless render_index
        raise "No render json found after @openapi error on line #{index + 1}"
      end

      snippet_end = [render_index + 15, end_index].min
      snippet = lines[render_index...snippet_end].join(" ")

      payload_match = snippet.match(
        /render\s+json:\s*\{.*?\b(error|errors|message)\s*:/m
      )

      unless payload_match
        raise "Could not identify error or errors key on line #{render_index + 1}"
      end

      payload_key = options["key"] || payload_match[1]

      literal_match = snippet.match(
        /\b(?:error|errors|message)\s*:\s*(?:\[\s*)?["']((?:\\.|[^"'])*)["']/m
      )

      message = options["example"] ||
        options["message"] ||
        literal_match&.captures&.first

      unless message
        raise <<~MESSAGE
          Could not infer the error message on line #{render_index + 1}.
          For dynamic errors, use:
          # @openapi error example:"A representative error message"
        MESSAGE
      end

      status_match = snippet.match(
        /status:\s*:(\w+)|status:\s*(\d{3})/
      )

      status = options["status"] ||
        status_match&.captures&.compact&.first

      status = http_status_code(status)

      errors << {
        "status" => status,
        "key" => payload_key,
        "message" => message,
        "description" => options["description"] || message
      }
    end

    errors
  end

  private

  def http_status_code(status)
    status_codes = {
      "bad_request" => "400",
      "unauthorized" => "401",
      "forbidden" => "403",
      "not_found" => "404",
      "conflict" => "409",
      "unprocessable_entity" => "422",
      "too_many_requests" => "429",
      "internal_server_error" => "500"
    }

    return status if status.to_s.match?(/\A[1-5]\d\d\z/)

    code = status_codes[status.to_s]

    unless code
      raise "Unknown HTTP status in @openapi error: #{status.inspect}"
    end

    code
  end
end
