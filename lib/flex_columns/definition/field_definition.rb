module FlexColumns
  module Definition
    class FieldDefinition
      attr_reader :name

      def initialize(column_definition, field_name, *args)
        @column_definition = column_definition
        @name = field_name.to_s.strip.downcase.to_sym
        @options = if args[-1] && args[-1].kind_of?(Hash) then args.pop else { } end

        raise ArgumentError, "Unexpected arguments: #{args.inspect}" if args.length > 0
      end

      def define_methods_on_flex_column!
        field_name = name

        column_definition.define_flex_column_method!(field_name) do
          self[field_name]
        end

        column_definition.define_flex_column_method!("#{field_name}=") do |x|
          self[field_name] = x
        end
      end

      def define_methods_on_model_class!
        field_name = name
        flex_column_name = column_definition.flex_column_name

        column_definition.define_dynamic_method_on_model_class!(field_name) do
          contents = send(flex_column_name)
          contents.send(field_name)
        end

        column_definition.define_dynamic_method_on_model_class!("#{field_name}=") do |x|
          contents = send(flex_column_name)
          contents.send("#{field_name}=", x)
        end
      end

      private
      attr_reader :column_definition
    end
  end
end
