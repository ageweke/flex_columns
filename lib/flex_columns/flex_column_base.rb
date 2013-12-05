require 'active_model'
require 'flex_columns/errors'
require 'flex_columns/field_definition'
require 'flex_columns/dynamic_methods_module'

module FlexColumns
  class FlexColumnBase
    include ActiveModel::Validations

    class << self
      def field(name, options = { })
        name = FlexColumns::FieldDefinition.normalize_name(name)

        @fields ||= { }
        @fields[name] = FlexColumns::FieldDefinition.new(self, name, options)

        sync_methods!
      end

      def is_flex_column_class?
        true
      end

      def has_any_validations?
        true
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

      def set_model_and_column!(model_class, column_name)
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

        @model_class = model_class
        @column = column

        class_name = "FlexColumn#{column_name.to_s.camelize}".to_sym
        @model_class.const_set(class_name, self)
      end

      attr_reader :model_class, :column

      private
      attr_reader :fields

      def sync_methods!
        @dynamic_methods_module ||= FlexColumns::DynamicMethodsModule.new(self, :FlexFieldsDynamicMethods)

        @dynamic_methods_module.remove_all_methods!
        model_class._flex_column_dynamic_methods_module.remove_all_methods!

        @fields.values.each do |field_definition|
          field_definition.add_methods_to_flex_column_class!(@dynamic_methods_module)
          field_definition.add_methods_to_model_class!(model_class._flex_column_dynamic_methods_module)
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
      out = field_contents[field_name]
      $stderr.puts "RETRIEVED: #{field_name.inspect} FROM: #{field_contents.inspect} -> #{out.inspect}"
      out
    end

    def []=(field_name, new_value)
      field_name = validate_and_deserialize_for_field(field_name)
      field_contents[field_name] = new_value
      $stderr.puts "SET: #{field_name.inspect} TO: #{new_value.inspect}, NOW: #{field_contents.inspect}"
      new_value
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

          @field_contents = parsed.symbolize_keys
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
