require 'json'

module FlexColumns
  module Contents
    class BaseContents
      include ::ActiveModel::Validations

      def initialize(model_instance, column_definition)
        @model_instance = model_instance
        @column_definition = column_definition
      end

      def [](field_name)
        assert_valid_field_name!(field_name)
        deserialize_if_necessary!

        fields[field_name]
      end

      def []=(field_name, new_value)
        assert_valid_field_name!(field_name)
        deserialize_if_necessary!

        fields[field_name] = new_value
      end

      def keys
        deserialize_if_necessary!
        fields.keys
      end

      def to_model
        self
      end

      def serialize!
        if fields
          model_instance[flex_column_name] = JSON.dump(fields)
        end
      end

      private
      attr_reader :model_instance, :column_definition
      attr_accessor :fields

      def flex_column_name
        column_definition.flex_column_name
      end

      def deserialize_if_necessary!
        return if @fields

        raw_data = model_instance[flex_column_name]
        raw_data = raw_data.strip if raw_data

        if raw_data && raw_data.length > 0
          parsed = JSON.parse(raw_data)

          raise "Invalid data: #{parsed.inspect}" unless parsed.kind_of?(Hash)
          @fields = parsed
        else
          @fields = { }
        end
      end

      def assert_valid_field_name!(field_name)
        raise "Invalid field name: #{field_name.inspect}" unless column_definition.has_field?(field_name)
      end
    end
  end
end
