#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'pathname'
require 'psych'
require 'rubygems'

REPO_ROOT = Pathname.new(__dir__).join('../..').realpath
TOOL_GEM_HOME = REPO_ROOT.join('.tools/ruby').to_s
system_gem_paths = Gem.path
Gem.use_paths(TOOL_GEM_HOME, [TOOL_GEM_HOME] + system_gem_paths)

begin
  gem 'json_schemer', '=2.2.1'
  require 'json_schemer'
rescue Gem::LoadError => e
  warn "missing pinned validation tools: #{e}; run tools/dev/bootstrap-test-tools.sh"
  exit 2
end

SCHEMAS = {
  'component' => REPO_ROOT.join('schemas/component.schema.json'),
  'stack' => REPO_ROOT.join('schemas/stack.schema.json'),
  'versions' => REPO_ROOT.join('schemas/versions.schema.json')
}.freeze

def load_document(path)
  Psych.safe_load(File.read(path), [], [], false)
end

def stack_profile_errors(document)
  return [] unless document.is_a?(Hash)

  defined_profiles = document.fetch('profiles', {}).keys
  document.fetch('components', []).each_with_index.flat_map do |component, index|
    next [] unless component.is_a?(Hash)

    component.fetch('profiles', []).each_with_object([]) do |profile, errors|
      unless defined_profiles.include?(profile)
        errors << "components.#{index}.profiles references undefined profile: #{profile}"
      end
    end
  end
end

kind, path_argument = ARGV
unless SCHEMAS.key?(kind) && path_argument
  warn "usage: #{File.basename($PROGRAM_NAME)} (#{SCHEMAS.keys.join('|')}) PATH"
  exit 2
end

path = Pathname.new(path_argument)
schema = JSON.parse(File.read(SCHEMAS.fetch(kind)))
document = load_document(path)
errors = JSONSchemer.schema(schema).validate(document).map do |error|
  pointer = error.fetch('data_pointer', '')
  details = error.fetch('details', {})
  value = error.key?('data') ? " value=#{error['data'].inspect}" : ''
  "#{pointer.empty? ? 'document' : pointer}: #{error.fetch('type')} #{details}#{value}"
end
errors.concat(stack_profile_errors(document)) if kind == 'stack'

errors.each { |error| warn "#{path}: #{error}" }
exit(errors.empty? ? 0 : 1)
