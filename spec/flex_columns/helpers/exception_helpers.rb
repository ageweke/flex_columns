module FlexColumns
  module Helpers
    module ExceptionHelpers
      def capture_exception(required_class = Exception, &block)
        e = nil
        begin
          block.call
        rescue required_class => x
          e = x
        end

        unless e
          raise "Expected an exception of class #{required_class.inspect}, but none was raised"
        end

        e
      end
    end
  end
end
