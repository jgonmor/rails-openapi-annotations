# frozen_string_literal: true

require_relative "annotations/version"

require "active_support/rails"
require "rails/railtie"

class Rails::Openapi::Annotations::Error < StandardError; end

module Rails::Openapi::Annotations::Parsers; end
module Rails::Openapi::Annotations::Builders; end

require_relative "annotations/configuration"
require_relative "annotations/railtie"
