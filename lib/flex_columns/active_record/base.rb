require 'active_record'
require 'active_support/concern'
require 'flex_columns/has_flex_columns'
require 'flex_columns/including/include_flex_columns'

module FlexColumns
  module ActiveRecord
    # This is the module that gets included into ::ActiveRecord::Base when +flex_columns+ is loaded. (No other changes
    # are made to the ActiveRecord API, except for classes where you've declared +flex_column+ or
    # +include_flex_columns_from+.) All it does is look for calls to our methods, and, when they are called, +include+
    # the correct module and then repeat the call again.
    module Base
      extend ActiveSupport::Concern

      # There are two ways you can end up with a flex-column object for a particular column name: either because your
      # model class declared that column as a flex column directly, or because you included flex columns from a model
      # that has that column declared as a flex column. This method allows us to dispatch to either, and correctly
      # returns the 'owned' object in preference if necessary.
      #
      # We used to use some complex magic with +super+ and defined a method of this name both in
      # FlexColumns::Including::IncludeFlexColumns and FlexColumns::HasFlexColumns, but Rails 4.0.3 or 4.0.4 broke that
      # due to some rejiggery in ActiveRecord::Base#method_missing. This seems like a significantly cleaner approach
      # anyway.
      def _flex_column_object_for(column_name, create_if_needed = true)
        return _flex_column_owned_object_for(column_name, create_if_needed) if respond_to?(:_flex_column_owned_object_for)
        return _flex_column_included_object_for(column_name) if respond_to?(:_flex_column_included_object_for)
        raise "FlexColumns: class #{self.class.name} seems to have no flex-column object for column #{column_name.inspect}, even though it internally asked for one; this is almost certainly a bug in the FlexColumns RubyGem. Please report it, and accept our apologies."
      end

      module ClassMethods
        # Does this class have any flex columns? FlexColumns::HasFlexColumns overrides this to return +true+.
        def has_any_flex_columns?
          false
        end

        # Declares a flex column. Includes FlexColumns::HasFlexColumns, and then does what looks like an
        # infinitely-recursing call -- but, because Ruby is so badass, this actually calls the method that has just
        # been included into the class, instead (i.e., the one from FlexColumns::HasFlexColumns).
        #
        # See FlexColumns::HasFlexColumns#flex_column for more information.
        def flex_column(*args, &block)
          include FlexColumns::HasFlexColumns
          flex_column(*args, &block)
        end

        # Includes flex columns from another class. Includes FlexColumns::Including::IncludeFlexColumns, and then does
        # what looks like an infinitely-recursing call -- but, because Ruby is so badass, this actually calls the method
        # that has just been included into the class, instead (i.e., the one from
        # FlexColumns::Including::IncludeFlexColumns).
        #
        # See FlexColumns::Including::IncludeFlexColumns#include_flex_columns_from for more information.
        def include_flex_columns_from(*args, &block)
          include FlexColumns::Including::IncludeFlexColumns
          include_flex_columns_from(*args, &block)
        end

        def _flex_columns_safe_to_define_method?(method_name)
          base_name = method_name.to_s
          base_name = $1 if base_name =~ /^(.*)=$/i

          reason = nil

          reason ||= :column if columns.detect { |c| c.name.to_s == base_name }
          # return false if method_defined?(base_name) || method_defined?("#{base_name}=")
          reason ||= :instance_method if instance_methods(false).map(&:to_s).include?(base_name.to_s)

          (! reason)
        end
      end
    end
  end
end
