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
        storage_string = nil

        if input.kind_of?(String)
          @model_instance = nil
          storage_string = input
          @source_string = input
        elsif (! input)
          @model_instance = nil
          storage_string = nil
        elsif input.class.equal?(self.class.model_class)
          @model_instance = input
          storage_string = @model_instance[self.class.column_name]
        else
          raise ArgumentError, %{You can create a #{self.class.name} from a String, nil, or #{self.class.model_class.name} (#{self.class.model_class.object_id}),
  not #{input.inspect} (#{input.object_id}).}
        end

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
          "(data passed in by client, for #{self.class.model_class.name}, column #{self.class.column_name.inspect})"
        end
      end

      # See the comment above FlexColumns::HasFlexColumns#read_attribute_for_serialization -- this is responsible for
      # correctly turning a flex-column object into a hash for serializing *the entire enclosing ActiveRecord model*.
      #
      # Most importantly, this method has NOTHING to do with our internal 'serialize a column as JSON' mechanisms. It
      # is ONLY called if you try to serialize the enclosing ActiveRecord instance.
      def to_hash_for_serialization
        @column_data.to_hash
      end

      # Make sure this flex-column object itself is smart enough to turn itself into JSON correctly.
      #
      # Most importantly, this method has NOTHING to do with our internal 'serialize a column as JSON' mechanisms. It
      # is ONLY called if you try to serialize something that in turn points directly to (i.e., not via the enclosing
      # ActiveRecord object) this flex-column object.
      def as_json(options = { })
        to_hash_for_serialization
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
          out[:source] = @source_string
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

      # Sometimes you want to deserialize a flex column explicitly, without actually changing anything in it. (For
      # example, if you set <tt>:unknown_fields => :delete</tt>, then unknown fields are removed from a column only if
      # it has been deserialized before you save it.) While you could accomplish this by simply accessing any field
      # of the column, it's cleaner and more clear what you're doing to just call this method.
      def touch!
        column_data.touch!
      end

      # Has the column been deserialized? A column is deserialized if someone has tried to read from or write to it,
      # or if someone has called #touch!.
      def deserialized?
        column_data.deserialized?
      end

      # Called via the ActiveRecord::Base#before_validation hook that gets installed on the enclosing model instance.
      # This runs any validations that are present on this flex-column object, and then propagates any errors back to
      # the enclosing model instance, so that errors show up there, as well.
      def before_validation!
        return unless model_instance
        unless valid?
          errors.each do |name, message|
            model_instance.errors.add("#{column_name}.#{name}", message)
          end
        end
      end

      INSPECT_MAXIMUM_LENGTH_FOR_ANY_ATTRIBUTE_VALUE = 100

      # **NOTE**: This method *WILL* deserialize the contents of the column, if it hasn't already been deserialized.
      # This is extremely useful for debugging, and almost certainly what you want, but if, for some reason, you
      # call #inspect on every single instance of a flex-column you get back from the database, you'll incur a
      # needless performance penalty. You have been warned.
      def inspect
        string_hash = { }
        column_data.to_hash.each do |k,v|
          v_string = v.to_s
          if v_string.length > INSPECT_MAXIMUM_LENGTH_FOR_ANY_ATTRIBUTE_VALUE
            v_string = "#{v_string[0..(INSPECT_MAXIMUM_LENGTH_FOR_ANY_ATTRIBUTE_VALUE - 1)]}..."
          end
          string_hash[k] = v_string
        end

        "<#{self.class.name}: #{string_hash.inspect}>"
      end

      # Returns a JSON string representing the current contents of this flex column. Note that this is _not_ always
      # exactly what gets stored in the database, because of binary columns and compression; for that, use
      # #to_stored_data, below.
      def to_json
        column_data.to_json
      end

      # Returns a String representing exactly the data that will get stored in the database, for this flex column.
      # This will be a UTF-8-encoded String containing pure JSON if this is a textual column, or, if it's a binary
      # column, either a UTF-8-encoded JSON String prefixed by a small header, or a BINARY-encoded String containing
      # GZip'ed JSON, prefixed by a small header.
      def to_stored_data
        column_data.to_stored_data
      end

      # Called via the ActiveRecord::Base#before_save hook that gets installed on the enclosing model instance. This is
      # what actually serializes the column data and sets it on the ActiveRecord model when it's being saved.
      def before_save!
        return unless model_instance

        # Make sure we only save if we need to -- otherwise, save the CPU cycles.
        if self.class.requires_serialization_on_save?(model_instance)
          model_instance[column_name] = column_data.to_stored_data
        end
      end

      # Returns an Array containing the names (as Symbols) of all fields on this flex-column object <em>that currently
      # have any data set for them</em> &mdash; _i.e._, that are not +nil+.
      def keys
        column_data.keys
      end

      private
      attr_reader :model_instance, :column_data

      # What's the name of the flex column itself?
      def column_name
        self.class.column_name
      end

      # What's the ActiveRecord ColumnDefinition object for this flex column?
      def column
        self.class.column
      end
    end
  end
end
