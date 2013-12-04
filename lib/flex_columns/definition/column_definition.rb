module FlexColumns
  module Definition
    class ColumnDefinition
      def initialize(definition_manager, flex_column_name, options, &block)
        @definition_manager = definition_manager
        @flex_column_name = flex_column_name.to_s.strip.downcase
        @options = options

        @fields = { }

        instance_eval(&block)
      end

      def flex_column_name
        @flex_column_name
      end

      def has_field?(field_name)
        @fields[field_name.to_s.strip.downcase]
      end

      def define_methods!
        fcn = flex_column_name

        definition_manager.define_direct_method!(flex_column_name) do
          _flex_columns_contents_manager.contents_for(fcn)
        end
      end

      def field(name)
        @fields[name.to_s.strip.downcase] = true
      end

      private
      attr_reader :definition_manager
    end
  end
end
