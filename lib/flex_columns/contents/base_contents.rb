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
        field_name = validate_field_name(field_name)
        deserialize_if_necessary!

        field_data[field_name]
      end

      def []=(field_name, new_value)
        field_name = validate_field_name(field_name)
        deserialize_if_necessary!

        field_data[field_name] = new_value
      end

      def keys
        deserialize_if_necessary!
        field_data.keys
      end

      def to_model
        self
      end

      def serialize!
        if field_data
          model_instance[flex_column_name] = JSON.dump(field_data.stringify_keys)
        end
      end

      private
      attr_reader :model_instance, :column_definition
      attr_accessor :field_data

      def flex_column_name
        column_definition.flex_column_name
      end

      def deserialize_if_necessary!
        return if @field_data

        raw_data = model_instance[flex_column_name]
        raw_data = raw_data.strip if raw_data

        if raw_data && raw_data.length > 0
          parsed = JSON.parse(raw_data)

          raise "Invalid data: #{parsed.inspect}" unless parsed.kind_of?(Hash)
          @field_data = parsed.symbolize_keys
        else
          @field_data = { }
        end
      end

      def validate_field_name(field_name)
        field_name = field_name.to_s.strip.downcase
        raise "Invalid field name: #{field_name.inspect}" unless column_definition.has_field?(field_name)
        field_name.to_sym
      end
    end
  end
end
