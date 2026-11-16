# frozen_string_literal: true

require_relative "lib/rails/openapi/annotations/version"

Gem::Specification.new do |spec|
  spec.name = "rails-openapi-annotations"
  spec.version = Rails::Openapi::Annotations::VERSION
  spec.authors = ["Jgonmor"]
  spec.email = ["contact@jgonmor.com"]
  spec.homepage = "https://github.com/jgonmor/rails-openapi-annotations"

  spec.summary = "Generate OpenAPI documentation from Rails controller annotations"
  spec.description = "A Rails extension that generates OpenAPI 3 documentation from compact controller annotations."
  spec.license = "GNU General Public License v3.0"
  spec.required_ruby_version = ">= 3.2.0"

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.end_with?(".gem") ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 7.0", "< 9.0"
  spec.add_dependency "activerecord", ">= 7.0", "< 9.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
