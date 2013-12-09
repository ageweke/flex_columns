require 'active_model'
require 'flex_columns/errors'
require 'flex_columns/dynamic_methods_module'
require 'flex_columns/column_data'
require 'flex_columns/field_set'
require 'flex_columns/flex_column_contents_class'

module FlexColumns
  class FlexColumnContentsBase
    include ActiveModel::Validations

    extend FlexColumns::FlexColumnContentsClass

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
