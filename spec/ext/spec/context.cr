# Copyright © 2017-2018 The SushiChain Core developers
#
# See the LICENSE file at the top-level directory of this distribution
# for licensing information.
#
# Unless otherwise agreed in a custom licensing agreement with the SushiChain Core developers,
# no part of this software, including this file, may be copied, modified,
# propagated, or distributed except according to the terms contained in the
# LICENSE file.
#
# Removal or modification of this copyright notice is prohibited.

module Spec
  # :nodoc:
  abstract class Context
  end

  # :nodoc:
  record Result,
    kind : Symbol,
    description : String,
    file : String,
    line : Int32,
    elapsed : Time::Span?,
    exception : Exception?

  # :nodoc:
  class RootContext < Context
    def initialize
      @results = {
        success: [] of Result,
        fail:    [] of Result,
        error:   [] of Result,
        pending: [] of Result,
        ignored: [] of Result,
      }
    end

    def parent
      nil
    end

    def succeeded
      @results[:fail].empty? && @results[:error].empty?
    end

    def self.report(kind, full_description, file, line, elapsed = nil, ex = nil)
      result = Result.new(kind, full_description, file, line, elapsed, ex)
      @@contexts_stack.last.report(result)
    end

    def report(result)
      Spec.formatters.each(&.report(result))

      @results[result.kind] << result
    end

    def self.print_results(elapsed_time, aborted = false)
      @@instance.print_results(elapsed_time, aborted)
    end

    def self.succeeded
      @@instance.succeeded
    end

    def self.finish(elapsed_time, aborted = false)
      @@instance.finish(elapsed_time, aborted)
    end

    def finish(elapsed_time, aborted = false)
      Spec.formatters.each(&.finish)
      Spec.formatters.each(&.print_results(elapsed_time, aborted))
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def print_results(elapsed_time, aborted = false)
      pendings = @results[:pending]
      unless pendings.empty?
        puts
        puts "Pending:"
        pendings.each do |pending|
          puts Spec.color("  #{pending.description}", :pending)
        end
      end

      ignoreds = @results[:ignored]
      unless ignoreds.empty?
        puts
        puts "Ignored:"
        ignoreds.each do |ignored|
          puts Spec.color("  #{ignored.description}", :ignored)
        end
      end

      failures = @results[:fail]
      errors = @results[:error]

      failures_and_errors = failures + errors
      unless failures_and_errors.empty?
        puts
        puts "Failures:"
        failures_and_errors.each_with_index do |fail, i|
          if ex = fail.exception
            puts
            puts "#{(i + 1).to_s.rjust(3, ' ')}) #{fail.description}"

            if ex.is_a?(SpecError)
              source_line = Spec.read_line(ex.file, ex.line)
              if source_line
                puts Spec.color("     Failure/Error: #{source_line.strip}", :error)
              end
            end
            puts

            message = ex.is_a?(SpecError) ? ex.to_s : ex.inspect_with_backtrace
            message.split('\n').each do |line|
              print "       "
              puts Spec.color(line, :error)
            end

            if ex.is_a?(SpecError)
              puts
              puts Spec.color("     # #{Spec.relative_file(ex.file)}:#{ex.line}", :comment)
            end
          end
        end
      end

      if Spec.slowest
        puts
        results = @results[:success] + @results[:fail]
        top_n = results.sort_by { |res| -res.elapsed.not_nil!.to_f }[0..Spec.slowest.not_nil!]
        top_n_time = top_n.sum &.elapsed.not_nil!.total_seconds
        percent = (top_n_time * 100) / elapsed_time.total_seconds
        puts "Top #{Spec.slowest} slowest examples (#{top_n_time} seconds, #{percent.round(2)}% of total time):"
        top_n.each do |res|
          puts "  #{res.description}"
          res_elapsed = res.elapsed.not_nil!.total_seconds.to_s
          if Spec.use_colors?
            res_elapsed = res_elapsed.colorize.bold
          end
          puts "    #{res_elapsed} seconds #{Spec.relative_file(res.file)}:#{res.line}"
        end
      end

      puts

      success = @results[:success]
      total = pendings.size + failures.size + errors.size + success.size

      final_status = case
                     when aborted                           then :error
                     when (failures.size + errors.size) > 0 then :fail
                     when pendings.size > 0                 then :pending
                     else                                        :success
                     end

      puts "Aborted!".colorize.red if aborted
      puts "Finished in #{Spec.to_human(elapsed_time)}"
      puts Spec.color("#{total} examples, #{failures.size} failures, #{errors.size} errors, #{pendings.size} pending, #{ignoreds.size} ignored", final_status)

      unless failures_and_errors.empty?
        puts
        puts "Failed examples:"
        puts
        failures_and_errors.each do |fail|
          print Spec.color("crystal spec #{Spec.relative_file(fail.file)}:#{fail.line}", :error)
          puts Spec.color(" # #{fail.description}", :comment)
        end
      end
    end

    @@instance = RootContext.new
    @@contexts_stack = [@@instance] of Context

    def self.describe(description, file, line, &block)
      describe = Spec::NestedContext.new(description, file, line, @@contexts_stack.last)
      @@contexts_stack.push describe
      Spec.formatters.each(&.push(describe))
      block.call
      Spec.formatters.each(&.pop)
      @@contexts_stack.pop
    end

    def self.matches?(description, pattern, line, locations)
      @@contexts_stack.any?(&.matches?(pattern, line, locations)) || description =~ pattern
    end

    def matches?(pattern, line, locations)
      false
    end

    @@spec_nesting = false

    def self.check_nesting_spec(file, line, &block)
      raise NestingSpecError.new("can't nest `it` or `pending`", file, line) if @@spec_nesting

      @@spec_nesting = true
      begin
        yield
      ensure
        @@spec_nesting = false
      end
    end
  end

  # :nodoc:
  class NestedContext < Context
    getter parent : Context
    getter description : String
    getter file : String
    getter line : Int32

    def initialize(@description : String, @file, @line, @parent)
    end

    def report(result)
      @parent.report Result.new(result.kind, "#{@description} #{result.description}", result.file, result.line, result.elapsed, result.exception)
    end

    def matches?(pattern, line, locations)
      return true if @description =~ pattern
      return true if @line == line

      if locations
        lines = locations[@file]?
        return true unless lines
        return lines.includes?(@line)
      end

      false
    end
  end
end
