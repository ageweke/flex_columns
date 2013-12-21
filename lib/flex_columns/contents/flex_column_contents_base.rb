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

      # A flex column has been "touched" if it has had at least one field changed to a different value than it had
      # before, or if someone has called #touch! on it. If a column has not been touched, validations are not run on it,
      # nor is it re-serialized back out to the database on save!. Generally, this is a good thing: it increases
      # performance substantially for times when you haven't actually changed the flex column's contents at all. It does
      # mean that invalid data won't be detected and unknown fields won't be removed (if you've specified
      # <tt>:unknown_fields => delete</tt>), however.
      #
      # There may be times, however, when you want to make sure the column is stored back out (including removing any
      # unknown fields, if you selected that option), or to make sure that validations get run, no matter what.
      # In this case, you can call #touch!.
      def touch!
        column_data.touch!
      end

      # Has at least one field in the column been changed, or has someone called #touch! ?
      def touched?
        column_data.touched?
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

        # We set the data only if someone has actually changed it, or if the column cannot be left NULL and it currently
        # is. (This latter case should generally only arise when creating a new row, but can also occur due to
        # migrations in certain bizarre circumstances, with certain databases that suck at such things. ;)
        if column_data.touched? || ((! column.null) && model_instance[column_name] == nil)
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
