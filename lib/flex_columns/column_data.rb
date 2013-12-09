require 'flex_columns/errors'
require 'stringio'
require 'zlib'

module FlexColumns
  class ColumnData
    def initialize(field_set, options = { })
      options.assert_valid_keys(:json_string, :field_set, :data_source, :unknown_fields, :length_limit, :storage, :compress_if_over_length)

      @json_string = options[:json_string]
      @field_set = options[:field_set]
      @data_source = options[:data_source]
      @unknown_fields = options[:unknown_fields]
      @length_limit = options[:length_limit]
      @storage = options[:storage]
      @compress_if_over_length = options[:compress_if_over_length]

      case json_string
      when nil, String then nil
      else raise ArgumentError, "Invalid JSON string: #{json_string.inspect}"
      end

      raise ArgumentError, "Must supply a FieldSet, not: #{field_set.inspect}" unless field_set.kind_of?(FlexColumns::FieldSet)
      raise ArgumentError, "Must supply a data source, not: #{data_source.inspect}" unless data_source
      raise ArgumentError, "Invalid value for :unknown_fields: #{unknown_fields.inspect}" unless [ :preserve, :delete ].include?(unknown_fields)
      raise ArgumentError, "Invalid value for :length_limit: #{length_limit.inspect}" if length_limit && (! (length_limit.kind_of?(Integer) && length_limit >= 8))
      raise ArgumentError, "Invalid value for :storage: #{storage.inspect}" unless [ :binary, :text ].include?(storage)
      raise ArgumentError, "Invalid value for :compress_if_over_length: #{compress_if_over_length.inspect}" if compress_if_over_length && (! compress_if_over_length.kind_of?(Integer))


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
      storage_hash.merge!(unknown_field_contents_by_key) unless unknown_fields == :delete

      field_contents_by_field_name.each do |field_name, field_contents|
        storage_name = field_set.field_named(field_name).json_storage_name
        storage_hash[storage_name] = field_contents
      end

      as_string = storage_hash.to_json

      if length_limit && as_string.length > length_limit
        raise FlexColumns::Errors::JsonTooLongError.new(data_source, length_limit, as_string)
      end

      as_string
    end

    def to_stored_data
      instrument("serialize") do
        json_string = to_json

        if storage == :binary
          json_string = json_string.force_encoding("BINARY") if json_string.respond_to?(:force_encoding)
          result = "%02d," % FLEX_COLUMN_CURRENT_VERSION_NUMBER

          compressed = nil
          if compress_if_over_length && json_string.length > compress_if_over_length
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
    attr_reader :json_string, :field_set, :data_source, :unknown_fields, :length_limit, :storage, :compress_if_over_length
    attr_reader :field_contents_by_field_name, :unknown_field_contents_by_key

    FLEX_COLUMN_CURRENT_VERSION_NUMBER = 1
    MIN_SIZE_REDUCTION_RATIO_FOR_COMPRESSION = 0.95

    def instrument(name, additional = { }, &block)
      ::ActiveSupport::Notifications.instrument("flex_columns.#{name}", data_source.notification_hash_for_flex_column_data_source.merge(additional), &block)
    end

    def validate_and_deserialize_for_field(field_name)
      field = field_set.field_named(field_name)
      unless field
        raise FlexColumns::Errors::NoSuchFieldError.new(data_source, field_name, field_set.all_field_names)
      end

      deserialize_if_necessary!

      field.field_name
    end

    def deserialize_if_necessary!
      unless field_contents_by_field_name
        raw_data = json_string || ''

        if raw_data.respond_to?(:valid_encoding?) && (! raw_data.valid_encoding?)
          raise FlexColumns::Errors::IncorrectlyEncodedStringInDatabaseError.new(data_source, raw_data)
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
                  data_source, raw_data, version_number, FLEX_COLUMN_CURRENT_VERSION_NUMBER)
              end

              case compressed
              when 0 then raw_data = remaining_data
              when 1 then
                input = StringIO.new(remaining_data)
                reader = Zlib::GzipReader.new(input)
                raw_data = reader.read
              else raise FlexColumns::Errors::InvalidDataInDatabaseError(
                data_source, raw_data, "the compression number was #{compressed.inspect}, not 0 or 1.")
              end
            end

            begin
              parsed = JSON.parse(raw_data)
            rescue ::JSON::ParserError => pe
              raise FlexColumns::Errors::UnparseableJsonInDatabaseError.new(data_source, raw_data, pe)
            end

            unless parsed.kind_of?(Hash)
              raise FlexColumns::Errors::InvalidJsonInDatabaseError.new(data_source, raw_data, parsed)
            end
          end

          @field_contents_by_field_name = { }
          @unknown_field_contents_by_key = { }

          parsed.each do |field_name, field_value|
            field = field_set.field_with_json_storage_name(field_name)
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
