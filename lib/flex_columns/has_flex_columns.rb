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
      _all_present_flex_column_objects.each do |flex_column_object|
        flex_column_object.before_save! if flex_column_object.touched?
      end
    end

    # Before we validate this model, make sure each flex column has a chance to run its validations and propagate any
    # errors back to this model. Note that we need to call through to any flex-column object that has a validation
    # defined, since we want to comply with Rails' validation strategy: validations run whenever you save an object,
    # whether you've changed that particular attribute or not.
    def _flex_columns_before_validation!
      _all_present_flex_column_objects.each do |flex_column_object|
        flex_column_object.before_validation! if flex_column_object.touched?
      end
    end

    # Returns the correct flex-column object for the given column name. This simply creates an instance of the
    # appropriate flex-column class, and saves it away so it will be returned again if someone requests the object for
    # the same column later.
    def _flex_column_object_for(column_name)
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
      _flex_column_objects[column_name] ||= self.class._flex_column_class_for(column_name).new(self)
    end

    # When you reload a model object, we should reload its flex-column objects, too.
    def reload(*args)
      super(*args)
      @_flex_column_objects = { }
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
      def has_any_flex_columns?
        true
      end

      def _all_flex_column_names
        _flex_column_classes.map(&:column_name)
      end

      def _flex_column_normalize_name(flex_column_name)
        flex_column_name.to_s.strip.downcase.to_sym
      end

      def _flex_column_class_for(flex_column_name)
        flex_column_name = _flex_column_normalize_name(flex_column_name)
        out = _flex_column_classes.detect { |fcc| fcc.column_name == flex_column_name }

        unless out
          raise FlexColumns::Errors::NoSuchColumnError, %{Model class #{self.name} has no flex column named #{flex_column_name.inspect};
it has flex columns named: #{_all_flex_column_names.sort_by(&:to_s).inspect}.}
        end

        out
      end

      def _flex_column_dynamic_methods_module
        @_flex_column_dynamic_methods_module ||= FlexColumns::Util::DynamicMethodsModule.new(self, :FlexColumnsDynamicMethods)
      end

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

      def create_flex_object_from(column_name, raw_string)
        _flex_column_class_for(column_name).new(raw_string)
      end

      def create_flex_objects_from(column_name, raw_strings)
        column_class = _flex_column_class_for(column_name)
        raw_strings.map do |rs|
          column_class.new(rs)
        end
      end

      private
      def _flex_column_classes
        @_flex_column_classes ||= [ ]
      end
    end
  end
end
