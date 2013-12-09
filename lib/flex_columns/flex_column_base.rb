require 'active_model'
require 'flex_columns/errors'
require 'flex_columns/dynamic_methods_module'
require 'flex_columns/column_data'
require 'flex_columns/field_set'

module FlexColumns
  class FlexColumnBase
    include ActiveModel::Validations

    class << self
      DEFAULT_MAX_JSON_LENGTH_BEFORE_COMPRESSION = 200

      def _flex_columns_create_column_data(json_string, data_source)
        create_options = {
          :json_string    => json_string,
          :data_source    => data_source,
          :unknown_fields => options[:unknown_fields] || :preserve,
          :length_limit   => column.limit,
          :storage        => column.type == :binary ? :binary : :text,
          :field_set      => field_set
        }

        if (! options.has_key?(:compress))
          create_options[:compress_if_over_length] = DEFAULT_MAX_JSON_LENGTH_BEFORE_COMPRESSION
        elsif options[:compress]
          create_options[:compress_if_over_length] = options[:compress]
        end

        FlexColumns::ColumnData.new(field_set, create_options)
      end

      def field(name, *args)
        field_set.field(name, *args)
      end

      def field_named(name)
        field_set.field_named(name)
      end

      def field_with_json_storage_name(json_storage_name)
        field_set.field_with_json_storage_name(json_storage_name)
      end

      def is_flex_column_class?
        true
      end

      def include_fields_into(dynamic_methods_module, association_name, options)
        field_set.include_fields_into(dynamic_methods_module, association_name, options)
      end

      def object_for(model_instance)
        model_instance._flex_column_object_for(column.name)
      end

      def delegation_prefix
        options[:prefix].try(:to_s)
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
        raise ArgumentError, "You can't call setup! twice!" if @model_class || @column

        unless model_class.kind_of?(Class) && model_class.respond_to?(:has_any_flex_columns?) && model_class.has_any_flex_columns?
          raise ArgumentError, "Invalid model class: #{model_class.inspect}"
        end

        raise ArgumentError, "Invalid column name: #{column_name.inspect}" unless column_name.kind_of?(Symbol)

        column = model_class.columns.detect { |c| c.name.to_s == column_name.to_s }
        unless column
          raise FlexColumns::Errors::NoSuchColumnError, %{You're trying to define a flex column #{column_name.inspect}, but
the model you're defining it on, #{model_class.name}, seems to have no column
named that.

It has columns named: #{model_class.columns.map(&:name).sort.join(", ")}.}
        end

        unless column.type == :binary || column.text?
          raise FlexColumns::Errors::InvalidColumnTypeError, %{You're trying to define a flex column #{column_name.inspect}, but
that column (on model #{model_class.name}) isn't of a type that accepts text.
That column is of type: #{column.type.inspect}.}
        end

        validate_options(options)

        @model_class = model_class
        @column = column
        @options = options
        @field_set = FlexColumns::FieldSet.new(self)

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

        field_set.add_delegated_methods!(@dynamic_methods_module, model_class._flex_column_dynamic_methods_module)
        add_custom_methods_to_model_class!(model_class._flex_column_dynamic_methods_module)
      end

      attr_reader :model_class

      private
      attr_reader :fields, :options, :custom_methods, :field_set, :column

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
      @column_data = self.class._flex_columns_create_column_data(json_string, self)
    end

    def describe_flex_column_data_source
      if model_instance
        out = self.class.model_class.name.dup
        out << " ID #{model_instance.id}" if model_instance.id
        out << ", column #{self.class.column_name.inspect}"
      else
        out << "(data passed in by client, for #{self.class.model_class.name}, column #{self.class.column_name.inspect})"
      end
    end

    def notification_hash_for_flex_column_data_source
      out = {
        :model_class => self.class.model_class,
        :column_name => self.class.column_name
      }

      if model_instance
        out[:model] = model_instance
      else
        out[:source] = :passed_string
      end

      out
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
      return unless model_instance
      unless valid?
        errors.each do |name, message|
          model_instance.errors.add("#{column_name}.#{name}", message)
        end
      end
    end

    def to_json
      column_data.to_json
    end

    def to_stored_data
      column_data.to_stored_data
    end

    def before_save!
      return unless model_instance
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
