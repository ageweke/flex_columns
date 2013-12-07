require 'flex_columns/utilities'

module FlexColumns
  module Errors
    class Base < ::StandardError
      private
      def maybe_model_instance_description
        if model_instance
          " on #{model_instance.class.name} ID #{model_instance.id.inspect}"
        else
          ""
        end
      end
    end

    class FieldError < Base; end
    class NoSuchFieldError < FieldError
      attr_reader :model_instance, :column_name, :field_name, :all_field_names

      def initialize(model_instance, column_name, field_name, all_field_names)
        @model_instance = model_instance
        @column_name = column_name
        @field_name = field_name
        @all_field_names = all_field_names

        super(%{You tried to set field #{field_name.inspect} of flex column #{column_name.inspect}
#{maybe_model_instance_description}. However, there is no such field
defined on that flex column; the defined fields are:

  #{all_field_names.join(", ")}})
      end
    end

    class DefinitionError < Base; end
    class NoSuchColumnError < DefinitionError; end
    class InvalidColumnTypeError < DefinitionError; end

    class DataError < Base; end

    class JsonTooLongError < DataError
      attr_reader :model_instance, :column_name, :limit, :json_string

      def initialize(model_instance, column_name, limit, json_string)
        @model_instance = model_instance
        @column_name = column_name
        @limit = limit
        @json_string = json_string

        super(%{When trying to serialize JSON for the flex column #{column_name.inspect}
#{maybe_model_instance_description}, the JSON produced was too long
to fit in the database. We produced #{json_string.length} characters of JSON, but the
database's limit for that column is #{limit} characters.

The JSON we produced was:

  #{FlexColumns::Utilities.abbreviated_string(json_string)}})
      end
    end

    class InvalidDataInDatabaseError < DataError
      attr_reader :model_instance, :column_name, :raw_string

      def initialize(model_instance, column_name, raw_string)
        @model_instance = model_instance
        @column_name = column_name
        @raw_string = raw_string

        super(create_message)
      end

      private
      def create_message
        %{When parsing the JSON#{maybe_model_instance_description}, which is:

#{FlexColumns::Utilities.abbreviated_string(raw_string)}

}
      end
    end

    class UnparseableJsonInDatabaseError < InvalidDataInDatabaseError
      attr_reader :json_exception

      def initialize(model_instance, column_name, raw_string, json_exception)
        super(model_instance, column_name, raw_string)
        @json_exception = json_exception
      end

      private
      def create_message
        super + %{, we got an exception: #{json_exception.message} (#{json_exception.class.name})}
      end
    end

    class InvalidJsonInDatabaseError < InvalidDataInDatabaseError
      attr_reader :returned_data

      def initialize(model_instance, column_name, raw_string, returned_data)
        super(model_instance, column_name, raw_string)
        @returned_data = returned_data
      end

      private
      def create_message
        super + %{, the JSON returned wasn't a Hash, but rather #{returned_data.class.name}:

#{FlexColumns::Utilities.abbreviated_string(returned_data.inspect)}}
      end
    end
  end
end
