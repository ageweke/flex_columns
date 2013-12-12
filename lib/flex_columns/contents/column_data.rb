require 'flex_columns/errors'
require 'stringio'
require 'zlib'

module FlexColumns
  module Contents
    # ColumnData is one of the core classes in +flex_columns+. An instance of ColumnData represents the data present
    # in a single row for a single flex column; it stores that data, is used to set and retrieve that data, and can
    # serialize and deserialize itself from and to JSON (with headers and optional compression added for binary storage).
    #
    # Clients do not interact with ColumnData itself; rather, they interact with an instance of a generated subclass
    # of FlexColumnsContentsBase, and it delegates core methods to this object.
    class ColumnData
      # Creates a new instance. +field_set+ is the FlexColumns::Definition::FieldSet that contains the set of fields
      # defined for this flex column; +options+ can contain:
      #
      # [:storage_string] The data present in the column in the database; this can be omitted if creating an instance
      #                   for a row that has no data, or for a new row.
      # [:data_source] Where did that data come from? This can be any object; it must respond to
      #                #describe_flex_column_data_source (no arguments), which should return a String that is used
      #                in thrown exceptions to let the client know what data caused the problem; it also must respond to
      #                #notification_hash_for_flex_column_data_source (no arguments), which should return a Hash that
      #                is used to generate the payload for the ActiveSupport::Notification calls this class makes.
      #                (This is, in practice, always an instance of the FlexColumnsContentsBase subclass generated for the
      #                column.)
      # [:unknown_fields] Must pass +:preserve+ or +:delete+. If there are keys in the serialized JSON that do not
      #                   correspond to any fields that the FieldSet knows about, this determines what will happen to
      #                   that data when re-serializing it to save: +:preserve+ keeps that data, while +:delete+ removes
      #                   it. (In neither case is that data actually accessible; you must declare a field if you want
      #                   access to it.)
      # [:length_limit] If present, specifies the maximum length of data that can be stored in the underlying storage
      #                 mechanism (the column). When serializing data, this object will raise an exception if the
      #                 serialized form is longer than this limit. This is used to avoid cases where the database might
      #                 otherwise silently truncate the data being stored (I'm looking at you, MySQL) and hence corrupt
      #                 stored data.
      # [:storage] This must be +:binary+ or +:text+. If +:text+, standard, uncompressed JSON will always be stored.
      #            (It is not possible to store compressed data reliably in a text column, because the database will
      #            interpret the bytes as characters and may modify them or raise an exception if byte sequences are
      #            present that would be invalid characters in whatever encoding it's using.) If :binary, then a very
      #            small header will be written that's just for versioning (currently +FC:01,+), followed by a marker
      #            indicating if it's compressed (+1,+) or not (+0,+), followed by either standard, uncompressed JSON
      #            encoded in UTF-8 or GZipped
      def initialize(field_set, options = { })
        options.assert_valid_keys(:storage_string, :data_source, :unknown_fields, :length_limit, :storage,
          :compress_if_over_length, :binary_header)

        @storage_string = options[:storage_string]
        @field_set = field_set
        @data_source = options[:data_source]
        @unknown_fields = options[:unknown_fields]
        @length_limit = options[:length_limit]
        @storage = options[:storage]
        @compress_if_over_length = options[:compress_if_over_length]
        @binary_header = options[:binary_header]

        raise ArgumentError, "Invalid JSON string: #{storage_string.inspect}" if storage_string && (! storage_string.kind_of?(String))
        raise ArgumentError, "Must supply a FieldSet, not: #{field_set.inspect}" unless field_set.kind_of?(FlexColumns::Definition::FieldSet)
        raise ArgumentError, "Must supply a data source, not: #{data_source.inspect}" unless data_source
        raise ArgumentError, "Invalid value for :unknown_fields: #{unknown_fields.inspect}" unless [ :preserve, :delete ].include?(unknown_fields)
        raise ArgumentError, "Invalid value for :length_limit: #{length_limit.inspect}" if length_limit && (! (length_limit.kind_of?(Integer) && length_limit >= 8))
        raise ArgumentError, "Invalid value for :storage: #{storage.inspect}" unless [ :binary, :text ].include?(storage)
        raise ArgumentError, "Invalid value for :compress_if_over_length: #{compress_if_over_length.inspect}" if compress_if_over_length && (! compress_if_over_length.kind_of?(Integer))
        raise ArgumentError, "Invalid value for :binary_header: #{binary_header.inspect}" unless [ true, false ].include?(binary_header)


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
          storage_hash[storage_name] = field_contents unless field_contents == nil
        end

        as_string = storage_hash.to_json
        as_string = as_string.encode(Encoding::UTF_8) if as_string.respond_to?(:encode)

        as_string
      end

      def to_stored_data
        out = nil

        instrument("serialize") do
          out = to_json
          out = to_binary_storage(out) if storage == :binary
        end

        if length_limit && out.length > length_limit
          raise FlexColumns::Errors::JsonTooLongError.new(data_source, length_limit, out)
        end

        out
      end

      private
      attr_reader :storage_string, :field_set, :data_source, :unknown_fields, :length_limit, :storage, :compress_if_over_length
      attr_reader :field_contents_by_field_name, :unknown_field_contents_by_key, :binary_header

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

      def to_binary_storage(json_string)
        json_string = json_string.force_encoding(Encoding::BINARY) if json_string.respond_to?(:force_encoding)
        return json_string if (! binary_header)

        header = "FC:%02d," % FLEX_COLUMN_CURRENT_VERSION_NUMBER

        if compress_if_over_length && json_string.length > compress_if_over_length
          compressed = compress(json_string)
          compressed.force_encoding(Encoding::BINARY) if compressed.respond_to?(:force_encoding)
          compressed = header + "1," + compressed
          compressed.force_encoding(Encoding::BINARY) if compressed.respond_to?(:force_encoding)
        end

        if compressed && compressed.length < (MIN_SIZE_REDUCTION_RATIO_FOR_COMPRESSION * json_string.length)
          compressed
        else
          header + "0," + json_string
        end
      end

      def compress(json_string)
        stream = StringIO.new("w")
        writer = Zlib::GzipWriter.new(stream)
        writer.write(json_string)
        writer.close

        stream.string
      end

      def decompress(data, raw_data)
        begin
          input = StringIO.new(data, "r")
          reader = Zlib::GzipReader.new(input)
          reader.read
        rescue Zlib::GzipFile::Error => gze
          raise FlexColumns::Errors::InvalidCompressedDataInDatabaseError.new(data_source, raw_data, gze)
        end
      end

      def from_stored_data(storage_string)
        if storage_string =~ /^(FC:(\d+),(\d+),)/i
          prefix = $1
          version_number = Integer($2)
          compressed = Integer($3)
          remaining_data = storage_string[prefix.length..-1]

          if version_number > FLEX_COLUMN_CURRENT_VERSION_NUMBER
            raise FlexColumns::Errors::InvalidFlexColumnsVersionNumberInDatabaseError.new(
              data_source, storage_string, version_number, FLEX_COLUMN_CURRENT_VERSION_NUMBER)
          end

          case compressed
          when 0 then remaining_data
          when 1 then decompress(remaining_data, storage_string)
          else raise FlexColumns::Errors::InvalidDataInDatabaseError.new(
            data_source, storage_string, "the compression number was #{compressed.inspect}, not 0 or 1.")
          end
        else
          storage_string
        end
      end

      def parse_json(json)
        out = begin
          JSON.parse(json)
        rescue ::JSON::ParserError => pe
          raise FlexColumns::Errors::UnparseableJsonInDatabaseError.new(data_source, json, pe)
        end

        unless out.kind_of?(Hash)
          raise FlexColumns::Errors::InvalidJsonInDatabaseError.new(data_source, json, out)
        end

        out
      end

      def store_fields!(parsed_hash)
        @field_contents_by_field_name = { }
        @unknown_field_contents_by_key = { }

        parsed_hash.each do |field_name, field_value|
          field = field_set.field_with_json_storage_name(field_name)
          if field
            @field_contents_by_field_name[field.field_name] = field_value
          else
            @unknown_field_contents_by_key[field_name] = field_value
          end
        end
      end

      def deserialize_if_necessary!
        unless field_contents_by_field_name
          raw_data = storage_string || ''

          if raw_data.respond_to?(:valid_encoding?) && (! raw_data.valid_encoding?)
            raise FlexColumns::Errors::IncorrectlyEncodedStringInDatabaseError.new(data_source, raw_data)
          end

          if raw_data.strip.length > 0
            parsed = instrument("deserialize", :raw_data => raw_data) do
              parse_json(from_stored_data(raw_data))
            end

            store_fields!(parsed)
          else
            @field_contents_by_field_name = { }
            @unknown_field_contents_by_key = { }
          end
        end
      end
    end
  end
end
