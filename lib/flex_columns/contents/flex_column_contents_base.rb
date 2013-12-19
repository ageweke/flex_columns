require 'active_model'
require 'flex_columns/errors'
require 'flex_columns/util/dynamic_methods_module'
require 'flex_columns/contents/column_data'
require 'flex_columns/definition/field_set'
require 'flex_columns/definition/flex_column_contents_class'

module FlexColumns
  module Contents
    # When you declare a flex column, we actually generate a brand-new Class for that column; instances of that flex
    # column are instances of this new Class. This class acquires functionality from two places: FlexColumnContentsBase,
    # which defines its instance methods, and FlexColumnContentsClass, which defines its class methods. (While
    # FlexColumnContentsBase is an actual Class, FlexColumnContentsClass is a Module that FlexColumnContentsBase
    # +extend+s. Both could be combined, but, simply for readability and maintainability, it was better to make them
    # separate.)
    #
    # This Class therefore defines the methods that are available on an instance of a flex-column class -- on the
    # object returned by <tt>my_user.user_attributes</tt>, for example.
    class FlexColumnContentsBase
      # Because of the awesome work done in Rails 3 to modularize ActiveRecord and friends, including this gives us
      # validation support basically for free.
      include ActiveModel::Validations

      # Grab all the class methods. :)
      extend FlexColumns::Definition::FlexColumnContentsClass

      # Creates a new instance. +input+ is the source of data we should use: normally this is an instance of the
      # enclosing model class (_e.g._, +User+), but it can also be a simple String (if you're creating an instance
      # using the bulk API -- +HasFlexColumns#create_flex_objects_from+, for example) containing the stored JSON for
      # this object, or +nil+ (if you're doing the same, but have no source data).
      #
      # The reason this class hangs onto the whole model instance, instead of just the string, is twofold:
      #
      # * It needs to be able to add validation errors back onto the model instance;
      # * It wants to be able to pass a description of the model instance into generated exceptions and the
      #   ActiveSupport::Notifications calls made, so that when things go wrong or you're doing performance work, you
      #   can understand what row in what table contains incorrect data or data that is making things slow.
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

        storage_string = raw_string || model_instance[self.class.column_name]

        # Creates an instance of FlexColumns::Contents::ColumnData, which is the thing that does most of the actual
        # work with the underlying data for us.
        @column_data = self.class._flex_columns_create_column_data(storage_string, self)
      end

      # Returns a String, appropriate for human consumption, that describes the model instance we're created from (or
      # raw String, if that's the case). This is used solely by the errors in FlexColumns::Errors, and is used to give
      # good, actionable diagnostic messages when something goes wrong.
      def describe_flex_column_data_source
        if model_instance
          out = self.class.model_class.name.dup
          out << " ID #{model_instance.id}" if model_instance.id
          out << ", column #{self.class.column_name.inspect}"
        else
          out << "(data passed in by client, for #{self.class.model_class.name}, column #{self.class.column_name.inspect})"
        end
      end

      # Returns a Hash, appropriate for integration into the payload of an ActiveSupport::Notification call, that
      # describes the model instance we're created from (or raw String, if that's the case). This is used by the
      # calls made to ActiveSupport::Notifications when a flex-column object is serialized or deserialized, and is used
      # to give good, actionable content when monitoring system performance.
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

      # This is required by ActiveModel::Validations; it's asking, "what's the ActiveModel object I should use for
      # validation purposes?". And, here, it's this same object.
      def to_model
        self
      end

      # Provides Hash-style read access to fields in the flex column. This delegates to the ColumnData object, which
      # does most of the actual work.
      def [](field_name)
        column_data[field_name]
      end

      # Provides Hash-style write access to fields in the flex column. This delegates to the ColumnData object, which
      # does most of the actual work.
      def []=(field_name, new_value)
        column_data[field_name] = new_value
      end

      # "Touches"
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
end
