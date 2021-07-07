# frozen_string_literal: true

require 'json'

module LicenseFinder
  class Bundler < PackageManager
    GroupDefinition = Struct.new(:groups)

    def initialize(options = {})
      super
      @ignored_groups = options[:ignored_groups]
    end

    def current_packages
      bundle_detail, gem_details = bundle_specs

      logger.debug self.class, "Bundler groups: #{bundle_detail.groups.inspect}", color: :green
      logger.debug self.class, "Ignored groups: #{ignored_groups.to_a.inspect}", color: :green

      gem_details.map do |gem_detail|
        BundlerPackage.new(gem_detail, bundle_detail, logger: logger).tap do |package|
          log_package_dependencies package
        end
      end
    end

    def package_management_command
      'bundle'
    end

    def prepare_command
      'bundle install'
    end

    def possible_package_paths
      [Dir.chdir(project_path) { gemfile_path }]
    end

    private

    attr_reader :ignored_groups

    def bundle_specs
      result = ''

      Dir.chdir(project_path) do
        pread, pwrite = IO.pipe
        env = ENV.to_h.dup
        env['BUNDLE_GEMFILE'] = gemfile_path.to_s
        pid = spawn(env, 'license_finder_bundler', *ignored_groups, out: pwrite)

        pwrite.close
        result = pread.read
        _pid, status = Process.wait2(pid)
        exit_status = status.exitstatus
        pread.close

        raise 'Unable to retrieve bundler gem specs' if exit_status != 0
        raise 'Unable to read bundler gem specs' if result.empty?
      end

      lf_bundler_def = JSON.parse(result)

      bundle_detail = GroupDefinition.new(lf_bundler_def['groups'])
      yaml_specs = lf_bundler_def['specs'].map { |gem_yaml| Gem::Specification.from_yaml(gem_yaml) }

      [bundle_detail, yaml_specs]
    end

    def gemfile_path
      gemfile_relative_path = ENV.fetch('BUNDLE_GEMFILE', './Gemfile')
      Pathname.new(gemfile_relative_path).expand_path(Dir.pwd)
    end

    def log_package_dependencies(package)
      dependencies = package.children
      if dependencies.empty?
        logger.debug self.class, format("package '%s' has no dependencies", package.name)
      else
        logger.debug self.class, format("package '%s' has dependencies:", package.name)
        dependencies.each do |dep|
          logger.debug self.class, format('- %s', dep)
        end
      end
    end
  end
end
