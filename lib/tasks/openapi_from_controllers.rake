# frozen_string_literal: true

require "rails/openapi/annotations/generator"

namespace :openapi do
  desc "Generate OpenAPI from compact controller annotations"

  task from_controllers: :environment do
    Rails::Openapi::Annotations::Generator.new.generate!
  end
end
