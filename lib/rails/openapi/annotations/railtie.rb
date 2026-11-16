# frozen_string_literal: true

module Rails
  module Openapi
    module Annotations
      class Railtie < ::Rails::Railtie
        rake_tasks do
          load File.expand_path(
            "../../../tasks/openapi_from_controllers.rake",
            __dir__
          )
        end
      end
    end
  end
end
