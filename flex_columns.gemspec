# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'flex_columns/version'

Gem::Specification.new do |s|
  s.name          = "flex_columns"
  s.version       = FlexColumns::VERSION
  s.authors       = ["Andrew Geweke"]
  s.email         = ["andrew@geweke.org"]
  s.homepage      = "https://github.com/ageweke/flex_columns"
  s.description   = %q{Provides flexible, schemaless columns in a RDBMS by using JSON serialization.}
  s.summary       = %q{Provides flexible, schemaless columns in a RDBMS by using JSON serialization.}
  s.license       = "MIT"

  s.files         = `git ls-files`.split($/)
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]

  s.add_development_dependency "bundler", "~> 1.3"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec", "~> 2.14"

  if (RUBY_VERSION =~ /^1\.9\./ || RUBY_VERSION =~ /^2\.0\./) && ((! defined?(RUBY_ENGINE)) || (RUBY_ENGINE != 'jruby'))
    s.add_development_dependency "pry"
    s.add_development_dependency "pry-debugger"
    s.add_development_dependency "pry-stack_explorer"
  end

  ar_version = ENV['FLEX_COLUMNS_AR_TEST_VERSION']
  ar_version = ar_version.strip if ar_version

  version_spec = case ar_version
  when nil then [ ">= 3.0", "<= 4.99.99" ]
  when 'master' then nil
  else [ "=#{ar_version}" ]
  end

  if version_spec
    s.add_dependency("activerecord", *version_spec)
  end

  s.add_dependency "activesupport", ">= 3.0", "<= 4.99.99"

  ar_import_version = case ar_version
  when nil then nil
  when 'master', /^4\.0\./ then '~> 0.4.1'
  when /^3\.0\./ then '~> 0.2.11'
  when /^3\.1\./, /^3\.2\./ then '~> 0.3.1'
  else raise "Don't know what activerecord-import version to require for activerecord version #{ar_version.inspect}!"
  end

  if ar_import_version
    s.add_dependency("activerecord-import", ar_import_version)
  else
    s.add_dependency("activerecord-import")
  end

  require File.expand_path(File.join(File.dirname(__FILE__), 'spec', 'flex_columns', 'helpers', 'database_helper'))
  database_gem_name = FlexColumns::Helpers::DatabaseHelper.maybe_database_gem_name

  # Ugh. Later versions of the 'mysql2' gem are incompatible with AR 3.0.x; so, here, we explicitly trap that case
  # and use an earlier version of that Gem.
  if database_gem_name && database_gem_name == 'mysql2' && ar_version && ar_version =~ /^3\.0\./
    s.add_development_dependency('mysql2', '~> 0.2.0')
  else
    s.add_development_dependency(database_gem_name)
  end
end
