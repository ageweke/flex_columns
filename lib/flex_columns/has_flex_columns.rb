require 'active_record'
require 'active_support/concern'
require 'active_support/core_ext'
require 'flex_columns/contents/flex_column_contents_base'

module FlexColumns
  # HasFlexColumns is the module that gets included in an ActiveRecord model class as soon as it declares a flex
  # column (using FlexColumns::ActiveRecord::Base#flex_column). While most of the actual work of maintaining and working
  # with a flex column is accomplished by the FlexColumns::Definition::FlexColumnContentsClass module and the
  # FlexColumns::Contents::FlexColumnContentsBase class, there remains, nevertheless, some important work to do here.
  module HasFlexColumns
    extend ActiveSupport::Concern

    # Register our hooks: we need to run before validation to make sure any validations defined directly on a flex
    # column class are run (and transfer their errors over to the model object itself), and to run before save to make
    # sure we serialize up any changes from a flex-column object.
    included do
      before_validation :_flex_columns_before_validation!
      before_save :_flex_columns_before_save!
    end

    # Before we save this model, make sure each flex column has a chance to serialize itself up and assign itself
    # properly to this model object. Note that we only need to call through to flex-column objects that have actually
    # been instantiated, since, by definition, there's no way the contents of any other flex columns could possibly
    # have been changed.
    def _flex_columns_before_save!
      self.class._all_flex_column_names.each do |flex_column_name|
        klass = self.class._flex_column_class_for(flex_column_name)
        if klass.requires_serialization_on_save?(self)
          _flex_column_object_for(flex_column_name).before_save!
        end
      end
    end

    # Before we validate this model, make sure each flex column has a chance to run its validations and propagate any
    # errors back to this model. Note that we need to call through to any flex-column object that has a validation
    # defined, since we want to comply with Rails' validation strategy: validations run whenever you save an object,
    # whether you've changed that particular attribute or not.
    def _flex_columns_before_validation!
      _all_present_flex_column_objects.each do |flex_column_object|
        flex_column_object.before_validation!
      end
    end

    # Returns the correct flex-column object for the given column name. This simply creates an instance of the
    # appropriate flex-column class, and saves it away so it will be returned again if someone requests the object for
    # the same column later.
    def _flex_column_object_for(column_name, create_if_needed = true)
      # It's possible to end up with two copies of this method on a class, if that class both has a flex column of its
      # own _and_ includes one via FlexColumns::Including::IncludeFlexColumns#include_flex_columns_from. If so, we want
      # each method to defer to the other one, so that both will work.
      begin
        return super(column_name)
      rescue NoMethodError
        # ok
      rescue FlexColumns::Errors::NoSuchColumnError
        # ok
      end

      column_name = self.class._flex_column_normalize_name(column_name)

      out = _flex_column_objects[column_name]
      if (! out) && create_if_needed
        out = _flex_column_objects[column_name] = self.class._flex_column_class_for(column_name).new(self)
      end
      out
    end

    # When ActiveRecord serializes an entire ActiveRecord object (for example, if you call #to_json on it), it
    # reads each column individually using this method -- which, in the default implementation, just calls #send.
    # (Well, it's actually *aliased* to #send, but it has the same effect.)
    #
    # However, if you're serializing an ActiveRecord model that contains a flex column, you almost certainly just
    # want that to behave as if the flex_column is a Hash, and serialize it that way. So we override it to do just
    # that right here.
    def read_attribute_for_serialization(attribute_name)
      if self.class._has_flex_column_named?(attribute_name)
        _flex_column_object_for(attribute_name).to_hash_for_serialization
      else
        super(attribute_name)
      end
    end

    # When you reload a model object, we should reload its flex-column objects, too.
    def reload(*args)
      out = super(*args)
      @_flex_column_objects = { }
      out
    end

    # This little-know ActiveRecord method gets called to produce a string for #inspect for a particular attribute.
    # Because the default implementation uses #read_attribute, if we don't override it, it will simply return our
    # actual string in the database; if this is compressed data, this is meaningless to a programmer. So we override
    # this to instead deserialize the column and call #inspect on the actual FlexColumnContentsBase object, which
    # shows interesting information.
    #
    # **NOTE**: See the warning comment above FlexColumnContentsBase#inspect, which points out that this will
    # deserialize the column if it hasn't already -- so calling this has a performance penalty. This should be fine,
    # since calling #inspect in bulk isn't something a program should be doing in production mode anyway, but it's
    # worth noting.
    def attribute_for_inspect(attr_name)
      cn =  self.class._all_flex_column_names
      if cn.include?(attr_name.to_sym)
        _flex_column_object_for(attr_name).inspect
      else
        super(attr_name)
      end
    end

    private
    # Returns the Hash that we keep flex-column objects in, indexed by column name.
    def _flex_column_objects
      @_flex_column_objects ||= { }
    end

    # Returns all flex-column objects that have been instantiated -- that is, any flex-column object that anybody has
    # asked for yet.
    def _all_present_flex_column_objects
      _flex_column_objects.values
    end

    module ClassMethods
      # Does this class have any flex columns? If this module has been included into a class, then the answer is true.
      def has_any_flex_columns?
        true
      end

      # What are the names of all flex columns defined on this model?
      def _all_flex_column_names
        _flex_column_classes.map(&:column_name)
      end

      # Does this model have a flex column with the given name?
      def _has_flex_column_named?(column_name)
        _all_flex_column_names.include?(_flex_column_normalize_name(column_name))
      end

      # Normalizes the name of a flex column, so we're consistent when using it for things like hash keys, no matter
      # how the client specifies it to us.
      def _flex_column_normalize_name(flex_column_name)
        flex_column_name.to_s.strip.downcase.to_sym
      end

      # Given the name of a flex column, returns the flex-column class for that column. Raises
      # FlexColumns::Errors::NoSuchColumnError if there is no column with the given name.
      def _flex_column_class_for(flex_column_name)
        flex_column_name = _flex_column_normalize_name(flex_column_name)
        out = _flex_column_classes.detect { |fcc| fcc.column_name == flex_column_name }

        unless out
          raise FlexColumns::Errors::NoSuchColumnError, %{Model class #{self.name} has no flex column named #{flex_column_name.inspect};
it has flex columns named: #{_all_flex_column_names.sort_by(&:to_s).inspect}.}
        end

        out
      end

      # Returns the DynamicMethodsModule that we add methods to that should be present on this model class.
      def _flex_column_dynamic_methods_module
        @_flex_column_dynamic_methods_module ||= FlexColumns::Util::DynamicMethodsModule.new(self, :FlexColumnsDynamicMethods)
      end

      # Declares a new flex column. +flex_column_name+ is its name; +options+ is passed through to
      # FlexColumns::Definition::FlexColumnContentsClass#setup!, and so can contain any of the options that that method
      # accepts. The block, if passed, will be evaluated in the context of the generated class.
      def flex_column(flex_column_name, options = { }, &block)
        flex_column_name = _flex_column_normalize_name(flex_column_name)

        new_class = Class.new(FlexColumns::Contents::FlexColumnContentsBase)
        new_class.setup!(self, flex_column_name, options, &block)

        _flex_column_classes.delete_if { |fcc| fcc.column_name == flex_column_name }
        _flex_column_classes << new_class

        define_method(flex_column_name) do
          _flex_column_object_for(flex_column_name)
        end

        _flex_column_dynamic_methods_module.remove_all_methods!
        _flex_column_classes.each(&:sync_methods!)
      end

      # Exactly like #create_flex_objects_from, except that instead of taking an Array of raw strings and returning
      # an Array of flex-column objects, takes a single raw string and returns a single flex-column object.
      #
      # #create_flex_objects_from is currently very slightly faster than simply calling this method in a loop; however,
      # in the future, the difference in performance may increase. If you have more than one string to create a
      # flex-column object from, you should definitely use #create_flex_objects_from instead of this method.
      def create_flex_object_from(column_name, raw_string)
        _flex_column_class_for(column_name).new(raw_string)
      end

      # Given the name of a column in +column_name+ and an Array of (possibly nil) JSON-formatted strings (which can
      # also be compressed using the +flex_columns+ compression mechanism), returns an Array of new flex-column objects
      # for that column that are not attached to any particular model instance. These objects will obey all
      # field-definition rules for that column, be able to validate themselves (if you call #valid? on them),
      # retrieve data, have any custom methods defined on them that you defined on that flex column, and so on.
      #
      # However, because they're detached from any model instance, they also won't save themselves to the database under
      # any circumstances; you are responsible for calling #to_stored_data on them, and getting those strings into the
      # database in the right places yourself, if you want to save them.
      #
      # The purpose of this method is to allow you to use +flex_columns+ in bulk-access situations, such as when you've
      # selected many records from the database without using ActiveRecord, for performance reasons (_e.g._,
      # <tt>User.connection.select_all("..."))</tt>.
      def create_flex_objects_from(column_name, raw_strings)
        column_class = _flex_column_class_for(column_name)
        raw_strings.map do |rs|
          column_class.new(rs)
        end
      end

      private
      # Returns the set of currently-active flex-column classes -- that is, classes that inherit from
      # FlexColumns::Contents::FlexColumnContentsBase and represent our declared flex columns. We say "currently active"
      # because declaring a new flex column with the same name as a previous one will replace its class in this list.
      #
      # This is an Array instead of a Hash because the order in which we sync methods to the dynamic-methods module
      # matters: flex columns declared later should have any delegate methods they declare supersede any methods from
      # flex columns declared previously. While Ruby >= 1.9 has ordered Hashes, which means we could use it here, we
      # still support Ruby 1.8, and so need the ordering that an Array gives us.
      def _flex_column_classes
        @_flex_column_classes ||= [ ]
      end
    end
  end
end
