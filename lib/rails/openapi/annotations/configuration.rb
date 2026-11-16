# frozen_string_literal: true

class Rails::Openapi::Annotations::Configuration
  attr_accessor :security_schemes,
    :security_requirement,
    :operation_builders,
    :response_overrides,
    :schemas,
    :request_body_overrides,
    :response_wrapper

  def initialize
    @security_schemes = {}
    @security_requirement = nil
    @operation_builders = {}
    @response_overrides = {}
    @schemas = {}
    @request_body_overrides = {}
    @response_wrapper = nil
  end

  def register_operation_builder(controller, builder)
    unless builder.respond_to?(:build_operation)
      raise ArgumentError, "Builder must respond to build_operation"
    end

    @operation_builders[controller.to_s] = builder
  end
end

module Rails::Openapi::Annotations
  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end

  def self.reset_configuration!
    @configuration = Configuration.new
  end
end
