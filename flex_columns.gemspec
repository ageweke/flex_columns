# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'flex_columns/version'

Gem::Specification.new do |spec|
  spec.name          = "flex_columns"
  spec.version       = FlexColumns::VERSION
  spec.authors       = ["Andrew Geweke"]
  spec.email         = ["andrew@geweke.org"]
  spec.homepage      = "https://github.com/ageweke/flex_columns"
  spec.description   = %q{Provides flexible, schemaless columns in a RDBMS by using JSON serialization.}
  spec.summary       = %q{Provides flexible, schemaless columns in a RDBMS by using JSON serialization.}
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
