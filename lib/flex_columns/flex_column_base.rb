require 'active_model'
require 'flex_columns/errors'
require 'flex_columns/field_definition'
require 'flex_columns/dynamic_methods_module'
require 'flex_columns/column_data'

module FlexColumns
  class FlexColumnBase
    include ActiveModel::Validations

    class << self
      def field(name, *args)
        options = args.pop if args[-1] && args[-1].kind_of?(Hash)
        options ||= { }

        name = FlexColumns::FieldDefinition.normalize_name(name)

        @fields ||= { }
        @fields_by_json_storage_names ||= { }

        field = FlexColumns::FieldDefinition.new(self, name, args, options)
        same_json_storage_name_field = @fields_by_json_storage_names[field.json_storage_name]
        if same_json_storage_name_field && same_json_storage_name_field.field_name != field.field_name
          raise FlexColumns::Errors::ConflictingJsonStorageNameError.new(model_class, column_name, name, same_json_storage_name_field.field_name, field.json_storage_name)
        end

        @fields[name] = field
        @fields_by_json_storage_names[field.json_storage_name] = field
      end

      def field_named(field_name)
        @fields[FlexColumns::FieldDefinition.normalize_name(field_name)]
      end

      def field_with_json_storage_name(json_storage_name)
        @fields_by_json_storage_names[FlexColumns::FieldDefinition.normalize_name(json_storage_name)]
      end

      def is_flex_column_class?
        true
      end

      MAX_JSON_LENGTH_BEFORE_COMPRESSION = 200

      def max_json_length_before_compression
        return options[:compress] if options[:compress].kind_of?(Integer)
        MAX_JSON_LENGTH_BEFORE_COMPRESSION
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

      def all_json_storage_names
        @fields.values.map(&:json_storage_name).sort_by(&:to_s)
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

        unless [ true, false, nil ].include?(options[:compress]) || options[:compress].kind_of?(Integer)
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
      raw_string = nil

      if input.kind_of?(String)
        @model_instance = nil
        raw_string = input
      elsif (! input)
        @model_instance = nil
      elsif input.class.equal?(self.class.model_class)
        @model_instance = input
      else
        raise ArgumentError, %{You can create a #{self.class.name} from a String, nil, or #{self.class.model_class.name} (#{self.class.model_class.object_id}),
not #{input.inspect} (#{input.object_id}).}
      end

      json_string = raw_string || model_instance[self.class.column_name]
      @column_data = FlexColumns::ColumnData.new(self.class, :json_string => json_string, :model_instance => @model_instance)
    end

    def to_model
      self
    end

    def [](field_name)
      column_data[field_name]
    end

    def []=(field_name, new_value)
      column_data[field_name] = new_value
    end

    def check!
      column_data.check!
    end

    def before_validation!
      unless valid?
        errors.each do |name, message|
          model_instance.errors.add("#{column_name}.#{name}", message)
        end
      end
    end

    def to_json
      column_data.to_json
    end

    def before_save!
      model_instance[column_name] = column_data.to_stored_data if column_data.touched?
    end

    def keys
      column_data.keys
    end

    private
    attr_reader :model_instance, :column_data

    def errors_object
      if model_instance
        model_instance.errors
      else
        @errors_object ||= ActiveModel::Errors.new(self)
      end
    end

    def column_name
      self.class.column_name
    end

    def column
      self.class.column
    end
  end
end
