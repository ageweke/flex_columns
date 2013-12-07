require 'active_model'
require 'flex_columns/errors'
require 'flex_columns/field_definition'
require 'flex_columns/dynamic_methods_module'

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

        unless column.text?
          raise FlexColumns::Errors::InvalidColumnTypeError, %{You're trying to define a flex column #{column_name.inspect}, but
that column (on model #{model_class.name}) isn't of a type that accepts text.
That column is of type: #{column.type.inspect}.}
        end

        validate_options(options)

        @model_class = model_class
        @column = column
        @options = options

        class_name = "FlexColumn#{column_name.to_s.camelize}".to_sym
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
        cn = column_name

        custom_methods.each do |custom_method|
          dynamic_methods_module.define_method(custom_method) do |*args, &block|
            flex_object = send(cn)
            flex_object.send(custom_method, *args, &block)
          end
        end
      end

      def validate_options(options)
        unless options.kind_of?(Hash)
          raise ArgumentError, "You must pass a Hash, not: #{options.inspect}"
        end

        options.assert_valid_keys(:visibility, :prefix, :delegate, :unknown_fields)

        unless [ nil, :private, :public ].include?(options[:visibility])
          raise ArgumentError, "Invalid value for :visibility: #{options[:visibility.inspect]}"
        end

        unless [ :delete, :preserve, nil ].include?(options[:unknown_fields])
          raise ArgumentError, "Invalid value for :unknown_fields: #{options[:unknown_fields].inspect}"
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

    def initialize(model_instance)
      unless model_instance.class.equal?(self.class.model_class)
        raise ArgumentError, %{Invalid model class for #{self.class.name}: should be #{self.class.model_class.name} (#{self.class.model_class.object_id}),
but is #{model_instance.class.name} (#{model_instance.class.object_id}).}
      end

      @model_instance = model_instance
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

    def deserialize_if_necessary!
      unless field_contents
        raw_data = (model_instance[column_name] || '').strip

        if raw_data.length > 0
          parsed = begin
            JSON.parse(raw_data)
          rescue JSON::ParserError => pe
            raise FlexColumns::Errors::UnparseableJsonInDatabaseError.new(model_instance, column_name, raw_data, pe)
          end

          unless parsed.kind_of?(Hash)
            raise FlexColumns::Errors::InvalidJsonInDatabaseError.new(model_instance, column_name, raw_data, parsed)
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

    def serialize_if_necessary!
      if field_contents
        as_string = field_contents.to_json
        if column.limit && as_string.length > column.limit
          raise FlexColumns::Errors::JsonTooLongError.new(model_instance, column_name, column.limit, as_string)
        end

        model_instance[column_name] = field_contents.to_json
      end
    end

    private
    attr_reader :model_instance, :field_contents

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
      self.class.column.name
    end

    def column
      self.class.column
    end
  end
end
