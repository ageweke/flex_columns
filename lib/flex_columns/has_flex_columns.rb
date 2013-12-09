require 'active_record'
require 'active_support/concern'
require 'active_support/core_ext'
require 'flex_columns/contents/flex_column_contents_base'

module FlexColumns
  module HasFlexColumns
    extend ActiveSupport::Concern

    included do
      before_validation :_flex_columns_before_validation!
      before_save :_flex_columns_before_save!
    end

    def _flex_columns_before_save!
      _all_present_flex_column_objects.each do |flex_column_object|
        flex_column_object.before_save!
      end
    end

    def _flex_columns_before_validation!
      self.class._all_flex_column_names.each do |column_name|
        _flex_column_object_for(column_name).before_validation!
      end
    end

    def _flex_column_object_for(column_name)
      column_name = self.class._flex_column_normalize_name(column_name)
      _flex_column_objects[column_name] ||= self.class._flex_column_class_for(column_name).new(self)
    end

    def _all_present_flex_column_objects
      _flex_column_objects.values
    end

    def reload(*args)
      super(*args)
      @_flex_column_objects = { }
    end

    private
    def _flex_column_objects
      @_flex_column_objects ||= { }
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
        @_flex_column_dynamic_methods_module ||= FlexColumns::DynamicMethodsModule.new(self, :FlexColumnsDynamicMethods)
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
