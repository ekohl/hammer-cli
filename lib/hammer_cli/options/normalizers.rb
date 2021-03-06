require 'json'
require 'hammer_cli/csv_parser'

module HammerCLI
  module Options
    module Normalizers

      class AbstractNormalizer
        def description
          ""
        end

        def format(val)
          raise NotImplementedError, "Class #{self.class.name} must implement method format."
        end

        def complete(val)
          []
        end
      end

      class Default < AbstractNormalizer
        def format(value)
          value
        end
      end

      class KeyValueList < AbstractNormalizer

        PAIR_RE = '([^,=]+)=([^,\[]+|\[[^\[\]]*\])'
        FULL_RE = "^((%s)[,]?)+$" % PAIR_RE

        def description
          _("Comma-separated list of key=value")
        end

        def format(val)
          return {} unless val.is_a?(String)
          return {} if val.empty?

          if valid_key_value?(val)
            parse_key_value(val)
          else
            begin
              formatter = JSONInput.new
              formatter.format(val)
            rescue ArgumentError
              raise ArgumentError, _("Value must be defined as a comma-separated list of key=value or valid JSON.")
            end
          end
        end

        private

        def valid_key_value?(val)
          Regexp.new(FULL_RE).match(val)
        end

        def parse_key_value(val)
          result = {}
          val.scan(Regexp.new(PAIR_RE)) do |key, value|
            value = value.strip
            value = value.scan(/[^,\[\]]+/) if value.start_with?('[')

            result[key.strip] = strip_value(value)
          end
          result
        end

        def strip_value(value)
          if value.is_a? Array
            value.map do |item|
              strip_chars(item.strip, '"\'')
            end
          else
            strip_chars(value.strip, '"\'')
          end
        end

        def strip_chars(string, chars)
          chars = Regexp.escape(chars)
          string.gsub(/\A[#{chars}]+|[#{chars}]+\z/, '')
        end
      end


      class List < AbstractNormalizer
        def description
          _("Comma separated list of values. Values containing comma should be quoted or escaped with backslash")
        end

        def format(val)
          (val.is_a?(String) && !val.empty?) ? HammerCLI::CSVParser.new.parse(val) : []
        end
      end


      class Number < AbstractNormalizer

        def format(val)
          if numeric?(val)
            val.to_i
          else
            raise ArgumentError, _("Numeric value is required.")
          end
        end

        def numeric?(val)
          Integer(val) != nil rescue false
        end

      end


      class Bool < AbstractNormalizer

        def description
          _('One of %s.') % ['true/false', 'yes/no', '1/0'].join(', ')
        end

        def format(bool)
          bool = bool.to_s
          if bool.downcase.match(/^(true|t|yes|y|1)$/i)
            return true
          elsif bool.downcase.match(/^(false|f|no|n|0)$/i)
            return false
          else
            raise ArgumentError, _('Value must be one of %s.') % ['true/false', 'yes/no', '1/0'].join(', ')
          end
        end

        def complete(value)
          ["yes ", "no "]
        end
      end


      class File < AbstractNormalizer

        def format(path)
          ::File.read(::File.expand_path(path))
        end

        def complete(value)
          Dir[value.to_s+'*'].collect do |file|
            if ::File.directory?(file)
              file+'/'
            else
              file+' '
            end
          end
        end
      end

      class JSONInput < File

        def format(val)
          # The JSON input can be either the path to a file whose contents are
          # JSON or a JSON string.  For example:
          #   /my/path/to/file.json
          # or
          #   '{ "units":[ { "name":"zip", "version":"9.0", "inclusion":"false" } ] }')
          json_string = ::File.exist?(::File.expand_path(val)) ? super(val) : val
          ::JSON.parse(json_string)

        rescue ::JSON::ParserError => e
          raise ArgumentError, _("Unable to parse JSON input.")
        end

      end


      class Enum < AbstractNormalizer
        attr_reader :allowed_values

        def initialize(allowed_values)
          @allowed_values = allowed_values
        end

        def description
          _("Possible value(s): %s") % quoted_values
        end

        def format(value)
          if @allowed_values.include? value
            value
          else
            if allowed_values.count == 1
              msg = _("Value must be %s.") % quoted_values
            else
              msg = _("Value must be one of %s.") % quoted_values
            end
            raise ArgumentError, msg
          end
        end

        def complete(value)
          Completer::finalize_completions(@allowed_values)
        end

        private

        def quoted_values
          @allowed_values.map { |v| "'#{v}'" }.join(', ')
        end
      end


      class DateTime < AbstractNormalizer

        def description
          _("Date and time in YYYY-MM-DD HH:MM:SS or ISO 8601 format")
        end

        def format(date)
          raise ArgumentError unless date
          ::DateTime.parse(date).to_s
        rescue ArgumentError
          raise ArgumentError, _("'%s' is not a valid date.") % date
        end
      end

      class EnumList < AbstractNormalizer

        def initialize(allowed_values)
          @allowed_values = allowed_values
        end

        def description
          _("Any combination (comma separated list) of '%s'") % quoted_values
        end

        def format(value)
          value.is_a?(String) ? parse(value) : []
        end

        def complete(value)
          Completer::finalize_completions(@allowed_values)
        end

        private

        def quoted_values
          @allowed_values.map { |v| "'#{v}'" }.join(', ')
        end

        def parse(arr)
          arr.split(",").uniq.tap do |values|
            unless values.inject(true) { |acc, cur| acc & (@allowed_values.include? cur) }
              raise ArgumentError, _("Value must be a combination of '%s'.") % quoted_values
            end
          end
        end
      end
    end
  end
end
