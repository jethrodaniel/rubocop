# frozen_string_literal: true

module RuboCop
  module Cop
    # This class takes a source buffer and rewrite its source
    # based on the different correction rules supplied.
    #
    # Important!
    # The nodes modified by the corrections should be part of the
    # AST of the source_buffer.
    class Corrector < ::Parser::Source::TreeRewriter
      # @param source [Parser::Source::Buffer, or anything
      #                leading to one via `(processed_source.)buffer`]
      #
      #   corrector = Corrector.new(cop)
      def initialize(source)
        source = self.class.source_buffer(source)
        super(
          source,
          different_replacements: :raise,
          swallowed_insertions: :raise,
          crossing_deletions: :accept
        )

        # Don't print warnings to stderr if corrections conflict with each other
        diagnostics.consumer = ->(diagnostic) {}
      end

      alias rewrite process # Legacy

      # TODO: move into plugin? https://github.com/rubocop-hq/rubocop-extension-generator
      #   https://github.com/rubocop-hq/rubocop/blob/6e270b5a1073121419d8d6353887187b7cfb17f5/docs/modules/ROOT/pages/extensions.adoc
      #
      # like {rewrite}, but interactive
      #
      # Actually, needs to handle a lot
      #
      # $ b exe/rubocop -a example.rb
      # Inspecting 1 file
      # C
      #
      # Offenses:
      #
      # > example.rb:1:1  Style/EmptyMethod: Put empty method definitions on a single line.
      #
      # -    def foo
      # +    def foo; end
      # -    end
      #
      # Stage this hunk [y/n/a/d/K/j/J/e/?]?
      #
      # example.rb:1:1: C: [Corrected|Skipped] Style/EmptyMethod: Put empty method definitions on a single line.

      def rewrite_interactive
        source     = @source_buffer.source

        # TODO: deal with infinite loop checker
        # lib/rubocop/runner.rb:284

        chunks = []
        last_end = 0
        @action_root.ordered_replacements.each do |range, replacement|
          last_end = range.end_pos
          old = source[range.begin_pos...last_end]
          new = source[last_end...range.begin_pos] << replacement

          choice = nil
          until %w(y yes n no).include? choice
            # TODO: offense name, file and line number
            # TODO: git style diff?
            puts "Correction xx at file:no"
            puts
            puts "== Before ==" # TODO: red
            puts
            puts "```"
            puts old
            puts "```"
            puts
            puts "== After ==" # TODO: green
            puts
            puts "```"
            puts new
            puts "```"
            puts
            print "(y/n): "

            choice = $stdin.gets.chomp

            puts "invalid choice"
          end

          case choice
          when "y", "yes"
            chunks << new
          else
            chunks << old
          end
        end

        chunks << source[last_end...source.length]
        chunks.join
      end

      # Removes `size` characters prior to the source range.
      #
      # @param [Parser::Source::Range, Rubocop::AST::Node] range or node
      # @param [Integer] size
      def remove_preceding(node_or_range, size)
        range = to_range(node_or_range)
        to_remove = range.with(
          begin_pos: range.begin_pos - size,
          end_pos:   range.begin_pos
        )
        remove(to_remove)
      end

      # Removes `size` characters from the beginning of the given range.
      # If `size` is greater than the size of `range`, the removed region can
      # overrun the end of `range`.
      #
      # @param [Parser::Source::Range, Rubocop::AST::Node] range or node
      # @param [Integer] size
      def remove_leading(node_or_range, size)
        range = to_range(node_or_range)
        to_remove = range.with(end_pos: range.begin_pos + size)
        remove(to_remove)
      end

      # Removes `size` characters from the end of the given range.
      # If `size` is greater than the size of `range`, the removed region can
      # overrun the beginning of `range`.
      #
      # @param [Parser::Source::Range, Rubocop::AST::Node] range or node
      # @param [Integer] size
      def remove_trailing(node_or_range, size)
        range = to_range(node_or_range)
        to_remove = range.with(begin_pos: range.end_pos - size)
        remove(to_remove)
      end

      # Duck typing for get to a ::Parser::Source::Buffer
      def self.source_buffer(source)
        source = source.processed_source if source.respond_to?(:processed_source)
        source = source.buffer if source.respond_to?(:buffer)
        source = source.source_buffer if source.respond_to?(:source_buffer)

        unless source.is_a? ::Parser::Source::Buffer
          raise TypeError, 'Expected argument to lead to a Parser::Source::Buffer ' \
                           "but got #{source.inspect}"
        end

        source
      end

      private

      # :nodoc:
      def to_range(node_or_range)
        range = case node_or_range
                when ::RuboCop::AST::Node, ::Parser::Source::Comment
                  node_or_range.loc.expression
                when ::Parser::Source::Range
                  node_or_range
                else
                  raise TypeError,
                        'Expected a Parser::Source::Range, Comment or ' \
                        "Rubocop::AST::Node, got #{node_or_range.class}"
                end
        validate_buffer(range.source_buffer)
        range
      end

      def check_range_validity(node_or_range)
        super(to_range(node_or_range))
      end

      def validate_buffer(buffer)
        return if buffer == source_buffer

        unless buffer.is_a?(::Parser::Source::Buffer)
          # actually this should be enforced by parser gem
          raise 'Corrector expected range source buffer to be a ' \
                "Parser::Source::Buffer, but got #{buffer.class}"
        end
        raise "Correction target buffer #{buffer.object_id} " \
              "name:#{buffer.name.inspect}" \
              " is not current #{@source_buffer.object_id} " \
              "name:#{@source_buffer.name.inspect} under investigation"
      end
    end
  end
end
