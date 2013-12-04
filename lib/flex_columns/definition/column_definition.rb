module FlexColumns
  module Definition
    class ColumnDefinition
      def initialize(definition_manager, flex_column_name, options, &block)
        @definition_manager = definition_manager
        @flex_column_name = flex_column_name.to_s.strip.downcase
        @options = options

        instance_eval(&block)
      end

      def flex_column_name
        @flex_column_name
      end

      def define_methods!
        definition_manager.define_direct_method!(flex_column_name) do
          12345
        end
      end

      def field(name)
        $stderr.puts "HAVE FIELD: #{name.inspect}"
      end

      private
      attr_reader :definition_manager
    end
  end
end
