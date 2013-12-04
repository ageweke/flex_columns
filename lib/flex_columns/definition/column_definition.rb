module FlexColumns
  module Definition
    class ColumnDefinition
      attr_reader :flex_column_name

      def initialize(columns_manager, flex_column_name, options, &block)
        @columns_manager = columns_manager
        @flex_column_name = flex_column_name.to_s.strip.downcase
        @options = options

        @fields = { }

        instance_eval(&block)
      end

      def has_field?(field_name)
        fields[field_name.to_s.strip.downcase]
      end

      def define_methods!
        fcn = flex_column_name

        columns_manager.define_direct_method!(flex_column_name) do
          _flex_columns_contents_manager.contents_for(fcn)
        end
      end

      def contents_class
        @contents_class ||= begin
          out = Class.new(FlexColumns::Contents::BaseContents)
          name = "#{flex_column_name.camelize}FlexContents".to_sym
          model_class.const_set(name, out)

          fields.keys.each do |field_name|
            out.send(:define_method, field_name) do
              self[field_name]
            end

            out.send(:define_method, "#{field_name}=") do |x|
              self[field_name] = x
            end
          end

          out
        end
      end

      def field(name)
        fields[name.to_s.strip.downcase] = true
      end

      private
      attr_reader :columns_manager, :fields

      def model_class
        columns_manager.model_class
      end
    end
  end
end
