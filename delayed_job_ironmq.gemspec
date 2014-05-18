require File.expand_path('../lib/delayed/backend/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Alexander Shapiotko", "Iron.io, Inc"]
  gem.email         = ["alex@iron.io", "support@iron.io"]
  gem.description   = "IronMQ backend for delayed_job"
  gem.summary       = "IronMQ backend for delayed_job"
  gem.homepage      = "https://github.com/iron-io/delayed_job_ironmq"
  gem.license       = "BSD-2-Clause"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "delayed_job_ironmq"
  gem.require_paths = ["lib"]
  gem.version       = Delayed::Backend::Ironmq::VERSION

  gem.required_rubygems_version = ">= 1.3.6"
  gem.required_ruby_version = Gem::Requirement.new(">= 1.8")
  gem.add_runtime_dependency "iron_mq", ">= 4.0.0"
  gem.add_runtime_dependency "delayed_job", ">= 3.0.0"

  gem.add_development_dependency "rspec"
end
