# frozen_string_literal: true
require "parallel_tests/test/runner"

module ParallelTests
  module Gherkin
    class Runner < ParallelTests::Test::Runner
      class << self
        def run_tests(test_files, process_number, num_processes, options)
          combined_scenarios = test_files

          if options[:group_by] == :scenarios
            grouped = test_files.map { |t| t.split(':') }.group_by(&:first)
            combined_scenarios = grouped.map do |file, files_and_lines|
              "#{file}:#{files_and_lines.map(&:last).join(':')}"
            end
          end

          options[:env] ||= {}
          options[:env] = options[:env].merge({ 'AUTOTEST' => '1' }) if $stdout.tty?

          execute_command(build_command(combined_scenarios, options), process_number, num_processes, options)
        end

        def test_file_name
          @test_file_name || 'feature'
        end

        def default_test_folder
          'features'
        end

        def test_suffix
          /\.feature$/
        end

        def line_is_result?(line)
          line =~ /^\d+ (steps?|scenarios?)/
        end

        def build_test_command(file_list, options)
          [
            *executable,
            *(runtime_logging if File.directory?(File.dirname(runtime_log))),
            *file_list,
            *cucumber_opts(options[:test_options])
          ]
        end

        # cucumber has 2 result lines per test run, that cannot be added
        # 1 scenario (1 failed)
        # 1 step (1 failed)
        def summarize_results(results)
          sort_order = ['scenario', 'step', 'failed', 'flaky', 'undefined', 'skipped', 'pending', 'passed']

          ['scenario', 'step'].map do |group|
            group_results = results.grep(/^\d+ #{group}/)
            next if group_results.empty?

            sums = sum_up_results(group_results)
            sums = sums.sort_by { |word, _| sort_order.index(word) || 999 }
            sums.map! do |word, number|
              plural = "s" if (word == group) && (number != 1)
              "#{number} #{word}#{plural}"
            end
            "#{sums[0]} (#{sums[1..].join(", ")})"
          end.compact.join("\n")
        end

        def cucumber_opts(given)
          if given&.include?('--profile') || given&.include?('-p')
            given
          else
            [*given, *profile_from_config]
          end
        end

        def profile_from_config
          # copied from https://github.com/cucumber/cucumber/blob/master/lib/cucumber/cli/profile_loader.rb#L85
          config = Dir.glob("{,.config/,config/}#{name}{.yml,.yaml}").first
          ['--profile', 'parallel'] if config && File.read(config) =~ /^parallel:/
        end

        def tests_in_groups(tests, num_groups, options = {})
          @test_file_name = "scenario" if options[:group_by] == :scenarios
          method = "by_#{options[:group_by]}"
          if Grouper.respond_to?(method)
            Grouper.send(method, find_tests(tests, options), num_groups, options)
          else
            super
          end
        end

        def runtime_logging
          ['--format', 'ParallelTests::Gherkin::RuntimeLogger', '--out', runtime_log]
        end

        def runtime_log
          "tmp/parallel_runtime_#{name}.log"
        end

        def determine_executable
          if File.exist?("bin/#{name}")
            ParallelTests.with_ruby_binary("bin/#{name}")
          elsif ParallelTests.bundler_enabled?
            ["bundle", "exec", name]
          elsif File.file?("script/#{name}")
            ParallelTests.with_ruby_binary("script/#{name}")
          else
            [name.to_s]
          end
        end
      end
    end
  end
end
