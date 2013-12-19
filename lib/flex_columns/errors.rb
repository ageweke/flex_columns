require 'flex_columns/util/string_utils'

module FlexColumns
  # This module contains definitions for all errors thrown by +flex_columns+. One of the goals of +flex_columns+ is to,
  # when an error occurs, raise an exception that has a great amount of detail about what happened -- in general, it
  # should be enough to know exactly where any invalid or problematic data came from, such as the row in the database
  # containing bad data, invalidly-encoded characters, or similar.
  module Errors
    # FlexColumns::Errors::Base: all +flex_columns+ errors inherit from this class.
    class Base < StandardError; end


    # FlexColumns::Errors::FieldError: all errors having to do with field definition inherit from this class.
    class FieldError < Base; end

    # Raised when you try to read or write data for a field that isn't defined.
    class NoSuchFieldError < FieldError
      attr_reader :data_source, :field_name, :all_field_names

      def initialize(data_source, field_name, all_field_names)
        @data_source = data_source
        @field_name = field_name
        @all_field_names = all_field_names

        super(%{You tried to set field #{field_name.inspect} of #{data_source.describe_flex_column_data_source}.
However, there is no such field defined on that flex column; the defined fields are:

  #{all_field_names.join(", ")}})
      end
    end

    # Raised when you try to define a field with the same JSON storage name, but a different field name, as a
    # previously-defined field.
    class ConflictingJsonStorageNameError < FieldError
      attr_reader :model_class, :column_name, :new_field_name, :existing_field_name, :json_storage_name

      def initialize(model_class, column_name, new_field_name, existing_field_name, json_storage_name)
        @model_class = model_class
        @column_name = column_name
        @new_field_name = new_field_name
        @existing_field_name = existing_field_name
        @json_storage_name = json_storage_name

        super(%{On class #{model_class.name}, flex column #{column_name.inspect}, you're trying to define a field,
#{new_field_name.inspect}, that has a JSON storage name of #{json_storage_name.inspect},
but there's already another field, #{existing_field_name.inspect}, that uses that same JSON storage name.

These fields would conflict in the JSON store, and thus this is not allowed.})
      end
    end


    # FlexColumns::Errors::DefinitionError: all errors having to do with definition of a flex column itself (not fields,
    # but the whole column) inherit from this class.
    class DefinitionError < Base; end

    # Raised when you try to define a flex_column for a column that doesn't exist in the database (at least according
    # to the model class).
    class NoSuchColumnError < DefinitionError; end

    # Raised when you try to define a flex_column for a column that isn't of a valid type for that -- for example, an
    # integer or a boolean column.
    class InvalidColumnTypeError < DefinitionError; end


    # FlexColumns::Errors::DataError: all errors having to do with the data present in a flex column in the database
    # inherit from this class.
    class DataError < Base; end

    # Raised when you try to store enough data in a flex column that the generated JSON is too long to fit into the
    # column.
    class JsonTooLongError < DataError
      attr_reader :data_source, :limit, :json_string

      def initialize(data_source, limit, json_string)
        @data_source = data_source
        @limit = limit
        @json_string = json_string

        super(%{When trying to serialize JSON for #{data_source.describe_flex_column_data_source},
the JSON produced was too long to fit in the database.
We produced #{json_string.length} characters of JSON, but the
database's limit for that column is #{limit} characters.

The JSON we produced was:

  #{FlexColumns::Util::StringUtils.abbreviated_string(json_string)}})
      end
    end

    # Raised when the JSON stored in the database is a valid Ruby String, but fails parsing (via JSON#parse).
    class InvalidDataInDatabaseError < DataError
      attr_reader :data_source, :raw_string, :additional_message

      def initialize(data_source, raw_string, additional_message = nil)
        @data_source = data_source
        @raw_string = raw_string
        @additional_message = additional_message

        super(create_message)
      end

      private
      def create_message
        out = %{When parsing the JSON in #{data_source.describe_flex_column_data_source}, which is:

#{FlexColumns::Util::StringUtils.abbreviated_string(raw_string)}

}
        out += additional_message if additional_message
        out
      end
    end

    # Raised when the data in the database appears to be GZip'ed, but we can't decompress that data.
    class InvalidCompressedDataInDatabaseError < InvalidDataInDatabaseError
      attr_reader :source_exception

      def initialize(data_source, raw_string, source_exception)
        @source_exception = source_exception
        super(data_source, raw_string)
      end

      private
      def create_message
        super + %{, we got an exception when trying to decompress the data:

#{source_exception} (#{source_exception.class.name})}
      end
    end

    class InvalidFlexColumnsVersionNumberInDatabaseError < InvalidDataInDatabaseError
      attr_reader :version_number_in_database, :max_version_number_supported

      def initialize(data_source, raw_string, version_number_in_database, max_version_number_supported)
        @version_number_in_database = version_number_in_database
        @max_version_number_supported = max_version_number_supported
        super(data_source, raw_string)
      end

      private
      def create_message
        super + %{, we got a version number in the database, #{version_number_in_database}, which is greater than our maximum supported version number, #{max_version_number_supported}.}
      end
    end

    class UnparseableJsonInDatabaseError < InvalidDataInDatabaseError
      attr_reader :source_exception

      def initialize(data_source, raw_string, source_exception)
        @source_exception = source_exception
        super(data_source, raw_string)
      end

      private
      def create_message
        source_message = source_exception.message

        if source_message.respond_to?(:force_encoding)
          source_message.force_encoding("UTF-8")
          source_message = source_message.chars.select { |c| c.valid_encoding? }.join
        end

        super + %{, we got an exception: #{source_message} (#{source_exception.class.name})}
      end
    end

    class IncorrectlyEncodedStringInDatabaseError < InvalidDataInDatabaseError
      attr_reader :invalid_chars_as_array, :raw_data_as_array, :first_bad_position

      def initialize(data_source, raw_string)
        @raw_data_as_array = raw_string.chars.to_a
        @valid_chars_as_array = [ ]
        @invalid_chars_as_array = [ ]
        @raw_data_as_array.each_with_index do |c, i|
          if (! c.valid_encoding?)
            @invalid_chars_as_array << c
            @first_bad_position ||= i
          else
            @valid_chars_as_array << c
          end
        end
        @first_bad_position ||= :unknown

        super(data_source, @valid_chars_as_array.join)
      end

      private
      def create_message
        extra = %{\n\nThere are #{invalid_chars_as_array.length} invalid characters out of #{raw_data_as_array.length} total characters.
(The string above showing the original JSON omits them, so that it's actually a valid String.)
The first bad character occurs at position #{first_bad_position}.

Some of the invalid chars are (in hex):

    }

        extra += invalid_chars_as_array[0..19].map { |c| c.unpack("H*") }.join(" ")

        super + extra
      end
    end

    class InvalidJsonInDatabaseError < InvalidDataInDatabaseError
      attr_reader :returned_data

      def initialize(data_source, raw_string, returned_data)
        super(data_source, raw_string)
        @returned_data = returned_data
      end

      private
      def create_message
        super + %{, the JSON returned wasn't a Hash, but rather #{returned_data.class.name}:

#{FlexColumns::Util::StringUtils.abbreviated_string(returned_data.inspect)}}
      end
    end
  end
end
