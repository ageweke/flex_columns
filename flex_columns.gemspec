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
  s.description   = %q{Schema-free, structured JSON storage inside a RDBMS.}
  s.summary       = %q{Schema-free, structured JSON storage inside a RDBMS.}
  s.license       = "MIT"

  s.files         = `git ls-files`.split($/)
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]

  s.add_dependency 'json'

  s.add_development_dependency "bundler", "~> 1.3"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec", "~> 2.14"

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

  # i18n released an 0.7.0 that's incompatible with Ruby 1.8.
  if RUBY_VERSION =~ /^1\.8\./
    s.add_development_dependency 'i18n', '< 0.7.0'
  end

  require File.expand_path(File.join(File.dirname(__FILE__), 'spec', 'flex_columns', 'helpers', 'database_helper'))
  database_gem_name = FlexColumns::Helpers::DatabaseHelper.maybe_database_gem_name

  # Ugh. Later versions of the 'mysql2' gem are incompatible with AR 3.0.x; so, here, we explicitly trap that case
  # and use an earlier version of that Gem.
  if database_gem_name && database_gem_name == 'mysql2' && ar_version && ar_version =~ /^3\.0\./
    s.add_development_dependency(database_gem_name, '~> 0.2.0')
  # The 'pg' gem removed Ruby 1.8 compatibility as of 0.18.
  elsif database_gem_name && database_gem_name == 'pg' && RUBY_VERSION =~ /^1\.8\./
    s.add_development_dependency(database_gem_name, '< 0.18.0')
  else
    s.add_development_dependency(database_gem_name)
  end
end
