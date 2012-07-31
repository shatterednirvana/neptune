require 'rubygems'
require 'rake/gempackagetask'

spec = Gem::Specification.new do |s|
  s.name = 'neptune'
  s.version = '0.2.2'

  s.summary = "A domain specific language for deploying HPC apps to cloud platforms"
  s.description = <<-EOF
    Neptune is a domain specific language that lets you deploy high performance
    computing applications to supported cloud platforms. Jobs can be deployed in
    standard Ruby syntax.
  EOF

  s.author = "Chris Bunch"
  s.email = "appscale_community@googlegroups.com"
  s.homepage = "http://neptune-lang.org"

  s.executables = ["neptune"]
  s.default_executable = 'neptune'
  s.platform = Gem::Platform::RUBY

  candidates = Dir.glob("{bin,doc,lib,test,samples}/**/*")
  s.files = candidates.delete_if do |item|
    item.include?(".bzr") || item.include?("rdoc")
  end
  s.require_path = "lib"
  s.autorequire = "neptune"

  s.has_rdoc = true
  s.extra_rdoc_files = ["README", "LICENSE"]

  # For Babel, which uses futures under the hood
  s.add_dependency('promise', '>= 0.3.0')
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_tar = true
end
