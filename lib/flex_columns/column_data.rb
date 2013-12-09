require 'flex_columns/errors'
require 'stringio'
require 'zlib'

module FlexColumns
  class ColumnData
    def initialize(flex_column_class, options = { })
      raise ArgumentError, "Flex column class must be a flex-column class, not: #{flex_column_class.inspect}" unless flex_column_class.superclass == FlexColumns::FlexColumnBase

      @flex_column_class = flex_column_class

      options.assert_valid_keys(:json_string, :model_instance)
      @json_string = options[:json_string]
      @model_instance = options[:model_instance]

      raise ArgumentError, "JSON string must be a String, not: #{@json_string.inspect}" if @json_string && (! @json_string.kind_of?(String))
      raise ArgumentError, "Model instance must be a model instance, not: #{@model_instance.inspect}" if @model_instance && (! @model_instance.kind_of?(flex_column_class.model_class))

      @field_contents_by_field_name = nil
      @unknown_field_contents_by_key = nil
    end

    def [](field_name)
      field_name = validate_and_deserialize_for_field(field_name)
      field_contents_by_field_name[field_name]
    end

    def []=(field_name, new_value)
      field_name = validate_and_deserialize_for_field(field_name)

      # We do this for a very good reason. When encoding as JSON, Ruby's JSON library happily accepts Symbols, but
      # encodes them as simple Strings in the JSON. (This makes sense, because JSON doesn't support Symbols.) This
      # means that if you save a value in a flex column as a Symbol, and then re-read that row from the database,
      # you'll get back a String, not the Symbol you put in.
      #
      # Unfortunately, this is different from what you'll get if there is no intervening save/load cycle, where it'd
      # otherwise stay a Symbol. This difference in behavior can be the source of some really annoying bugs. While
      # ActiveRecord has this annoying behavior, this is a chance to clean it up in a small way -- so, if you set a
      # Symbol, we return a String. (And, yes, this has no bearing on Symbols stored nested inside Arrays or Hashes;
      # and that's OK.)
      new_value = new_value.to_s if new_value.kind_of?(Symbol)

      field_contents_by_field_name[field_name] = new_value
    end

    def keys
      deserialize_if_necessary!
      field_contents_by_field_name.keys.sort_by(&:to_s)
    end

    def check!
      deserialize_if_necessary!
    end

    def touched?
      !! field_contents_by_field_name
    end

    def to_json
      deserialize_if_necessary!

      storage_hash = { }
      storage_hash.merge!(unknown_field_contents_by_key) unless flex_column_class.unknown_field_action == :delete

      field_contents_by_field_name.each do |field_name, field_contents|
        storage_name = flex_column_class.field_named(field_name).json_storage_name
        storage_hash[storage_name] = field_contents
      end

      as_string = storage_hash.to_json

      if flex_column_class.column.limit && as_string.length > flex_column_class.column.limit
        raise FlexColumns::Errors::JsonTooLongError.new(model_instance, flex_column_class.column_name, flex_column_class.column.limit, as_string)
      end

      as_string
    end

    def to_stored_data
      instrument("serialize") do
        json_string = to_json

        if flex_column_class.is_binary_column?
          json_string = json_string.force_encoding("BINARY") if json_string.respond_to?(:force_encoding)
          result = "%02d," % FLEX_COLUMN_CURRENT_VERSION_NUMBER

          compressed = nil
          if flex_column_class.can_compress? && json_string.length > flex_column_class.max_json_length_before_compression
            output = StringIO.new("w")
            writer = Zlib::GzipWriter.new(output)
            writer.write(json_string)
            writer.close

            compressed = output.string
          end

          if compressed && compressed.length < (MIN_SIZE_REDUCTION_RATIO_FOR_COMPRESSION * json_string.length)
            result += "1,"
            result.force_encoding("BINARY") if json_string.respond_to?(:force_encoding)

            result += compressed
          else
            result += "0,"
            result.force_encoding("BINARY") if json_string.respond_to?(:force_encoding)
            result += json_string
          end

          result
        else
          json_string
        end
      end
    end

    private
    attr_reader :flex_column_class, :json_string, :model_instance, :field_contents_by_field_name, :unknown_field_contents_by_key

    FLEX_COLUMN_CURRENT_VERSION_NUMBER = 1
    MIN_SIZE_REDUCTION_RATIO_FOR_COMPRESSION = 0.95

    def instrument(name, additional = { }, &block)
      base = {
        :model_class => flex_column_class.model_class,
        :model => model_instance,
        :column_name => flex_column_class.column_name
      }

      ::ActiveSupport::Notifications.instrument("flex_columns.#{name}", base.merge(additional), &block)
    end

    def delete_unknown_fields_from!(hash)
      extra = (hash.keys - self.class.all_json_storage_names)
      extra.each { |e| hash.delete(e) }
    end

    def validate_and_deserialize_for_field(field_name)
      field = flex_column_class.field_named(field_name)
      unless field
        raise FlexColumns::Errors::NoSuchFieldError.new(model_instance, flex_column_class.column_name, field_name, flex_column_class.all_field_names)
      end

      deserialize_if_necessary!

      field.field_name
    end

    def deserialize_if_necessary!
      unless @field_contents_by_field_name
        raw_data = json_string || ''

        if raw_data.respond_to?(:valid_encoding?) && (! raw_data.valid_encoding?)
          raise FlexColumns::Errors::IncorrectlyEncodedStringInDatabaseError.new(model_instance, flex_column_class.column_name, raw_data)
        end

        raw_data = raw_data.strip

        if raw_data.length > 0
          parsed = nil

          instrument("deserialize", :raw_data => raw_data) do
            if raw_data =~ /^((\d+),(\d+),)/i
              prefix = $1
              version_number = Integer($2)
              compressed = Integer($3)
              remaining_data = raw_data[prefix.length..-1]

              if version_number > FLEX_COLUMN_CURRENT_VERSION_NUMBER
                raise FlexColumns::Errors::InvalidFlexColumnsVersionNumberInDatabaseError(
                  model_instance, flex_column_class.column_name, raw_data, version_number, FLEX_COLUMN_CURRENT_VERSION_NUMBER)
              end

              case compressed
              when 0 then raw_data = remaining_data
              when 1 then
                input = StringIO.new(remaining_data)
                reader = Zlib::GzipReader.new(input)
                raw_data = reader.read
              else raise FlexColumns::Errors::InvalidDataInDatabaseError(
                model_instance, flex_column_class.column_name, raw_data, "the compression number was #{compressed.inspect}, not 0 or 1.")
              end
            end

            begin
              parsed = JSON.parse(raw_data)
            rescue ::JSON::ParserError => pe
              raise FlexColumns::Errors::UnparseableJsonInDatabaseError.new(model_instance, flex_column_class.column_name, raw_data, pe)
            end

            unless parsed.kind_of?(Hash)
              raise FlexColumns::Errors::InvalidJsonInDatabaseError.new(model_instance, flex_column_class.column_name, raw_data, parsed)
            end
          end

          @field_contents_by_field_name = { }
          @unknown_field_contents_by_key = { }

          parsed.each do |field_name, field_value|
            field = flex_column_class.field_with_json_storage_name(field_name)
            if field
              @field_contents_by_field_name[field.field_name] = field_value
            else
              @unknown_field_contents_by_key[field_name] = field_value
            end
          end
        else
          @field_contents_by_field_name = { }
          @unknown_field_contents_by_key = { }
        end
      end
    end
  end
end
