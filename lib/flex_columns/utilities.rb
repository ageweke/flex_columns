module FlexColumns
  class Utilities
    class << self
      MAX_LENGTH_FOR_ABBREVIATED_STRING = 100
      ABBREVIATED_STRING_SEPARATOR = "..."

      def abbreviated_string(s)
        if s && s.length > MAX_LENGTH_FOR_ABBREVIATED_STRING
          component_size = ((MAX_LENGTH_FOR_ABBREVIATED_STRING - ABBREVIATED_STRING_SEPARATOR.length) / 2.0).floor
          "#{s[0..(component_size - 1)]}#{ABBREVIATED_STRING_SEPARATOR}#{s[(-component_size + 1)..-1]}"
        else
          s
        end
      end
    end
  end
end
