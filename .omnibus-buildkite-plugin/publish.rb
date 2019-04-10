#!/usr/bin/env ruby

require 'artifactory'
require 'fileutils'
require 'json'
require 'omnibus'
require 'tempfile'
require 'rubygems/commands/push_command'
require 'yaml'

ARCHITECTURE_PACKAGE_PATTERN = '-(aarch64|i386|i86pc|powerpc|ppc64|ppc64le|s390x|sun4v|x86_64)'.freeze
OMNIBUS_PACKAGE_PATTERN = '**/pkg/*.{bff,deb,dmg,msi,p5p,rpm,solaris,amd64.sh,i386.sh}'.freeze

def self.env_or_empty(key)
  ENV[key] || ''
end

def self.env_or_raise(key)
  ENV[key] || raise("Required ENV variable `#{key}` is unset!")
end

project_name                   = env_or_raise('PROJECT_NAME')
omnibus_pipeline_definition_path = env_or_raise('OMNIBUS_PIPELINE_DEFINITION_PATH')
artifactory_endpoint           = env_or_raise('ARTIFACTORY_ENDPOINT')
artifactory_base_path          = env_or_raise('ARTIFACTORY_BASE_PATH')
artifactory_username           = env_or_raise('ARTIFACTORY_USERNAME')
artifactory_password           = env_or_raise('ARTIFACTORY_PASSWORD')

package_glob_pattern = "./#{OMNIBUS_PACKAGE_PATTERN}"

puts "Publishing with glob pattern of #{package_glob_pattern}"
puts ''

builder_to_testers_map = Hash.new { |h, k| h[k] = [] }
if File.exist?(omnibus_pipeline_definition_path)
  omnibus_pipeline_definition = YAML.safe_load(File.read(omnibus_pipeline_definition_path))

  omnibus_pipeline_definition['builder-to-testers-map'].each do |builder, testers|
    shortened_builder = builder.sub(/#{ARCHITECTURE_PACKAGE_PATTERN}/, "")
    shortened_testers = testers.map { |tester| tester.sub(/#{ARCHITECTURE_PACKAGE_PATTERN}/, "") }
    builder_to_testers_map[shortened_builder].concat(shortened_testers)
    builder_to_testers_map[shortened_builder].uniq!
  end
  builder_to_testers_map = builder_to_testers_map.map do |k, v|
    # We name the platform/version slightly different in Solaris:
    if k =~ /solaris-(\d)*/
      platform_splitter = proc do |p|
        p, pv = p.rpartition('-') - %w( - )
        "#{p}2-5.#{pv}"
      end

      [platform_splitter.call(k), v.map { |p| platform_splitter.call(p) }]
    else
      [k, v]
    end
  end.to_h
end

Omnibus::Config.artifactory_endpoint(artifactory_endpoint)
Omnibus::Config.artifactory_base_path(artifactory_base_path)
Omnibus::Config.artifactory_username(artifactory_username)
Omnibus::Config.artifactory_password(artifactory_password)
publisher = Omnibus::ArtifactoryPublisher.new(
  package_glob_pattern,
  repository: 'omnibus-unstable-local',
  platform_mappings: builder_to_testers_map,
  build_record: false
)

if publisher.packages.empty?
  raise "Could not locate any #{project_name} artifacts to publish."
else
  publisher.publish do |package|
    puts "Published '#{package.name}' for #{package.metadata[:platform]}-#{package.metadata[:platform_version]}"
  end

  puts <<-EOH

DONE! \\m/

  EOH
end

# We need to push the gems in certain cases (ie chef, chef-dk)
if %w(chef chefdk).include?(project_name) && (ENV['ADHOC'] != 'true')
  GEM_PACKAGE_PATTERN = '**/[^/]*\.gem'.freeze
  gem_base_name = (project_name == 'chefdk') ? 'chef-dk' : project_name
  project_source = "#{Omnibus::Config.base_dir}/**/src/#{gem_base_name}"

  # This will exclude any gems in a /spec/ directory
  gems_found = Dir.glob("#{project_source}/#{GEM_PACKAGE_PATTERN}") - Dir.glob("#{project_source}/**/spec/#{GEM_PACKAGE_PATTERN}")

  # Sometimes there are multiple copies of a gem on disk -- only upload one copy.
  gems_to_publish = gems_found.uniq { |gem| File.basename(gem) }

  puts "Publishing Gems from #{project_source}"
  puts ''

  gems_to_publish.each do |gem_path|
    puts 'Publishing gem ' + gem_path
    artifactory_endpoint = "#{Omnibus::Config.artifactory_endpoint}/api/gems/omnibus-gems-local"
    # This mimics the behavior of the gem command line, and is a public api:
    # http://docs.seattlerb.org/rubygems/Gem/Command.html
    gem_pusher = Gem::Commands::PushCommand.new
    gem_pusher.handle_options [gem_path, '--host', artifactory_endpoint, '--key', 'artifactory_api_key', '--verbose']
    gem_pusher.execute
  end
end
