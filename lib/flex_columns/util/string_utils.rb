module FlexColumns
  module Util
    # Contains a single method for abbreviating strings.
    #
    # Yes, this is very un-Ruby-like -- to define a separate utility function, rather than just adding a method to
    # String. However, this method is used in such limited context (generating exception messages) that polluting the
    # namespace of one of the most important classes in Ruby is probably a pretty bad idea.
    class StringUtils
      class << self
        MAX_LENGTH_FOR_ABBREVIATED_STRING = 100
        ABBREVIATED_STRING_SEPARATOR = "..."

        # Returns a string of length no more than MAX_LENGTH_FOR_ABBREVIATED_STRING, by eliding, if necessary,
        # characters from the middle. This is used when throwing exceptions: +flex_columns+ can generate very long
        # strings of JSON data, and having many kilobytes (or even megabytes) of JSON make its way into an exception
        # message is probably a really bad idea.
        def abbreviated_string(s)
          if s && s.length > MAX_LENGTH_FOR_ABBREVIATED_STRING
            before_separator_length = ((MAX_LENGTH_FOR_ABBREVIATED_STRING - ABBREVIATED_STRING_SEPARATOR.length) / 2.0).floor
            out = s[0..(before_separator_length - 1)] + ABBREVIATED_STRING_SEPARATOR
            remaining = MAX_LENGTH_FOR_ABBREVIATED_STRING - out.length
            out << s[(-remaining + 1)..-1]
            out
          else
            s
          end
        end
      end
    end
  end
end
