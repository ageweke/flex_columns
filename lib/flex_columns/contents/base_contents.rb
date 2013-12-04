require 'json'

module FlexColumns
  module Contents
    class BaseContents
      def initialize(model_instance, column_definition)
        @model_instance = model_instance
        @column_definition = column_definition

        deserialize!
      end

      def [](field_name)
        assert_valid_field_name!(field_name)
        fields[field_name]
      end

      def []=(field_name, new_value)
        assert_valid_field_name!(field_name)
        fields[field_name] = new_value
      end

      def serialize!
        @model_instance[column_definition.flex_column_name] = JSON.dump(fields)
      end

      private
      attr_reader :model_instance, :column_definition
      attr_accessor :fields

      def deserialize!
        raw_data = model_instance[column_definition]
        self.fields = { }
      end

      def assert_valid_field_name!(field_name)
        raise "Invalid field name: #{field_name.inspect}" unless column_definition.has_field?(field_name)
      end
    end
  end
end
