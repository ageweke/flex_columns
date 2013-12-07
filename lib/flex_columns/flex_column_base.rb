require 'active_model'
require 'flex_columns/errors'
require 'flex_columns/field_definition'
require 'flex_columns/dynamic_methods_module'
require 'stringio'
require 'zlib'

module FlexColumns
  class FlexColumnBase
    include ActiveModel::Validations

    class << self
      def field(name, *args)
        options = args.pop if args[-1] && args[-1].kind_of?(Hash)
        options ||= { }

        name = FlexColumns::FieldDefinition.normalize_name(name)

        @fields ||= { }
        @fields[name] = FlexColumns::FieldDefinition.new(self, name, args, options)
      end

      def is_flex_column_class?
        true
      end

      def has_any_validations?
        true
      end

      def include_fields_into(dynamic_methods_module, association_name, options)
        @fields.values.each do |field_definition|
          field_definition.add_methods_to_included_class!(dynamic_methods_module, association_name, options)
        end
      end

      def to_valid_field_name(field_name)
        field_name = FlexColumns::FieldDefinition.normalize_name(field_name)
        field_name if fields[field_name]
      end

      def all_field_names
        @fields.keys.sort_by { |x| x.to_s }
      end

      def object_for(model_instance)
        model_instance._flex_column_object_for(column.name)
      end

      def delegation_prefix
        options[:prefix].try(:to_s)
      end

      def unknown_field_action
        options[:unknown_fields] || :preserve
      end

      def new_from_raw_string(rs)
        new(rs)
      end

      def new_from_nothing
        new(nil)
      end

      def delegation_type
        return :public if (! options.has_key?(:delegate))

        case options[:delegate]
        when nil, false then nil
        when true, :public then :public
        when :private then :private
        else raise "Impossible value for :delegate: #{options[:delegate]}"
        end
      end

      def column_name
        column.name.to_sym
      end

      def fields_are_private_by_default?
        options[:visibility] == :private
      end

      def is_binary_column?
        @is_binary_column
      end

      def can_compress?
        is_binary_column? && (! (options.has_key?(:compress) && (! options[:compress])))
      end

      def setup!(model_class, column_name, options = { }, &block)
        raise ArgumentError, "You can't set model and column twice!" if @model_class || @column

        unless model_class.kind_of?(Class) && model_class.respond_to?(:has_any_flex_columns?) && model_class.has_any_flex_columns?
          raise ArgumentError, "Invalid model class: #{model_class.inspect}"
        end

        unless column_name.kind_of?(Symbol)
          raise ArgumentError, "Invalid column name: #{column_name.inspect}"
        end

        column = model_class.columns.detect { |c| c.name.to_s == column_name.to_s }
        unless column
          raise FlexColumns::Errors::NoSuchColumnError, %{You're trying to define a flex column #{column_name.inspect}, but
the model you're defining it on, #{model_class.name}, seems to have no column
named that.

It has columns named: #{model_class.columns.map(&:name).sort.join(", ")}.}
        end

        if column.type == :binary
          @is_binary_column = true
        elsif column.text?
          @is_binary_column = false
        else
          raise FlexColumns::Errors::InvalidColumnTypeError, %{You're trying to define a flex column #{column_name.inspect}, but
that column (on model #{model_class.name}) isn't of a type that accepts text.
That column is of type: #{column.type.inspect}.}
        end

        validate_options(options)

        @model_class = model_class
        @column = column
        @options = options

        class_name = "FlexColumn#{column_name.to_s.camelize}".to_sym
        @model_class.send(:remove_const, class_name) if @model_class.const_defined?(class_name)
        @model_class.const_set(class_name, self)

        methods_before = instance_methods
        class_eval(&block) if block
        @custom_methods = (instance_methods - methods_before).map(&:to_sym)
      end

      def sync_methods!
        @dynamic_methods_module ||= FlexColumns::DynamicMethodsModule.new(self, :FlexFieldsDynamicMethods)
        @dynamic_methods_module.remove_all_methods!

        @fields.values.each do |field_definition|
          field_definition.add_methods_to_flex_column_class!(@dynamic_methods_module)
          field_definition.add_methods_to_model_class!(model_class._flex_column_dynamic_methods_module)
          add_custom_methods_to_model_class!(model_class._flex_column_dynamic_methods_module)
        end
      end

      attr_reader :model_class, :column

      private
      attr_reader :fields, :options, :custom_methods

      def add_custom_methods_to_model_class!(dynamic_methods_module)
        return if (! delegation_type)

        cn = column_name

        custom_methods.each do |custom_method|
          dynamic_methods_module.define_method(custom_method) do |*args, &block|
            flex_object = send(cn)
            flex_object.send(custom_method, *args, &block)
          end

          dynamic_methods_module.private(custom_method) if delegation_type == :private
        end
      end

      def validate_options(options)
        unless options.kind_of?(Hash)
          raise ArgumentError, "You must pass a Hash, not: #{options.inspect}"
        end

        options.assert_valid_keys(:visibility, :prefix, :delegate, :unknown_fields, :compress)

        unless [ nil, :private, :public ].include?(options[:visibility])
          raise ArgumentError, "Invalid value for :visibility: #{options[:visibility.inspect]}"
        end

        unless [ :delete, :preserve, nil ].include?(options[:unknown_fields])
          raise ArgumentError, "Invalid value for :unknown_fields: #{options[:unknown_fields].inspect}"
        end

        unless [ true, false, nil ].include?(options[:compress])
          raise ArgumentError, "Invalid value for :compress: #{options[:compress].inspect}"
        end

        case options[:prefix]
        when nil then nil
        when String, Symbol then nil
        else raise ArgumentError, "Invalid value for :prefix: #{options[:prefix].inspect}"
        end

        unless [ nil, true, false, :private, :public ].include?(options[:delegate])
          raise ArgumentError, "Invalid value for :delegate: #{options[:delegate].inspect}"
        end

        if options[:visibility] == :private && options[:delegate] == :public
          raise ArgumentError, "You can't have public delegation if methods in the flex column are private; this makes no sense, as methods in the model class would have *greater* visibility than methods on the flex column itself"
        end
      end
    end

    def initialize(input)
      if input.kind_of?(String)
        @model_instance = nil
        @raw_string = input
      elsif (! input)
        @model_instance = nil
        @raw_string = nil
      elsif input.class.equal?(self.class.model_class)
        @model_instance = input
        @raw_string = nil
      else
        raise ArgumentError, %{You can create a #{self.class.name} from a String, nil, or #{self.class.model_class.name} (#{self.class.model_class.object_id}),
not #{input.inspect} (#{input.object_id}).}
      end

      @field_contents = nil
    end

    def to_model
      self
    end

    def [](field_name)
      field_name = validate_and_deserialize_for_field(field_name)
      field_contents[field_name]
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

      field_contents[field_name] = new_value
    end

    def check!
      deserialize_if_necessary!
    end

    def before_validation!
      unless valid?
        errors.each do |name, message|
          model_instance.errors.add("#{column_name}.#{name}", message)
        end
      end
    end

    def before_save!
      serialize_if_necessary!
    end

    def keys
      deserialize_if_necessary!
      field_contents.keys.sort_by { |x| x.to_s }
    end

    def instrument(name, additional = { }, &block)
      base = {
        :model_class => self.class.model_class,
        :model => model_instance,
        :column_name => column_name
      }

      ::ActiveSupport::Notifications.instrument("flex_columns.#{name}", base.merge(additional), &block)
    end

    def deserialize_if_necessary!
      unless field_contents
        raw_data = if model_instance then model_instance[column_name] else raw_string end
        raw_data ||= ''

        if raw_data.respond_to?(:valid_encoding?) && (! raw_data.valid_encoding?)
          raise FlexColumns::Errors::IncorrectlyEncodedStringInDatabaseError.new(model_instance, column_name, raw_data)
        end

        raw_data = raw_data.strip

        if raw_data.length > 0
          parsed = nil

          instrument("deserialize", :raw_data => raw_data) do
            if raw_data =~ /^(\d+),(\d+),(.*)$/i
              version_number = Integer($1)
              compressed = Integer($2)
              remaining_data = $3

              if version_number > FLEX_COLUMN_CURRENT_VERSION_NUMBER
                raise FlexColumns::Errors::InvalidFlexColumnsVersionNumberInDatabaseError(model_instance, column_name, raw_data, version_number, FLEX_COLUMN_CURRENT_VERSION_NUMBER)
              end

              case compressed
              when 0 then raw_data = remaining_data
              when 1 then
                input = StringIO.new(remaining_data)
                reader = Zlib::GzipReader.new(input)
                raw_data = reader.read
              else raise FlexColumns::Errors::InvalidDataInDatabaseError(model_instance, column_name, raw_data, "the compression number was #{compressed.inspect}, not 0 or 1.")
              end
            end

            begin
              parsed = JSON.parse(raw_data)
            rescue ::JSON::ParserError => pe
              raise FlexColumns::Errors::UnparseableJsonInDatabaseError.new(model_instance, column_name, raw_data, pe)
            end

            unless parsed.kind_of?(Hash)
              raise FlexColumns::Errors::InvalidJsonInDatabaseError.new(model_instance, column_name, raw_data, parsed)
            end
          end

          parsed = parsed.symbolize_keys

          if self.class.unknown_field_action == :delete
            delete_unknown_fields_from!(parsed)
          end

          @field_contents = parsed
        else
          @field_contents = { }
        end
      end
    end

    FLEX_COLUMN_CURRENT_VERSION_NUMBER = 1
    MAX_JSON_LENGTH_BEFORE_COMPRESSION = 200

    def serialize_if_necessary!
      if field_contents
        instrument("serialize") do
          json_string = to_json

          if self.class.is_binary_column?
            json_string = json_string.force_encoding("BINARY") if json_string.respond_to?(:force_encoding)
            result = "%02d," % FLEX_COLUMN_CURRENT_VERSION_NUMBER

            if self.class.can_compress? && json_string.length > MAX_JSON_LENGTH_BEFORE_COMPRESSION
              result += "1,"
              result.force_encoding("BINARY") if json_string.respond_to?(:force_encoding)

              output = StringIO.new("w")
              writer = Zlib::GzipWriter.new(output)
              writer.write(json_string)
              writer.close

              result += output.string
            else
              result += "0,"
              result.force_encoding("BINARY") if json_string.respond_to?(:force_encoding)
              result += json_string
            end

            model_instance[column_name] = result
          else
            model_instance[column_name] = to_json
          end
        end
      end
    end

    def to_json
      deserialize_if_necessary!

      as_string = field_contents.to_json
      if column.limit && as_string.length > column.limit
        raise FlexColumns::Errors::JsonTooLongError.new(model_instance, column_name, column.limit, as_string)
      end

      field_contents.to_json
    end

    private
    attr_reader :model_instance, :field_contents, :raw_string

    def errors_object
      if model_instance
        model_instance.errors
      else
        @errors_object ||= ActiveModel::Errors.new(self)
      end
    end

    def delete_unknown_fields_from!(hash)
      extra = (hash.keys - self.class.all_field_names)
      extra.each { |e| hash.delete(e) }
    end

    def validate_and_deserialize_for_field(field_name)
      valid_field_name = self.class.to_valid_field_name(field_name)
      unless valid_field_name
        raise FlexColumns::Errors::NoSuchFieldError.new(model_instance, column_name, field_name, self.class.all_field_names)
      end

      deserialize_if_necessary!

      valid_field_name
    end

    def column_name
      self.class.column_name
    end

    def column
      self.class.column
    end
  end
end
