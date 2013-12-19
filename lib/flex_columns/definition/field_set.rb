require 'flex_columns/errors'
require 'flex_columns/definition/field_definition'

module FlexColumns
  module Definition
    # A FieldSet keeps track of a set of FieldDefinition objects for a particular flex-column contents calss. It's largely
    # a wrapper around this set that allows you to add fields (via #field), find fields based on their name or JSON
    # storage name, return all field names, and invoke certain delegation methods across all fields.
    class FieldSet
      # Create a new instance for the given class that inherits from FlexColumnContentsBase.
      def initialize(flex_column_class)
        @flex_column_class = flex_column_class
        @fields = { }
        @fields_by_json_storage_names = { }
      end

      # Defines a new field. This is passed through directly by the flex-column contents class -- its semantics are therefore
      # exactly what the client sees. +name+ is the name of the new field, and +args+ receives any additional arguments
      # (type, options, etc.).
      def field(name, *args)
        # Peel off the options
        options = args.pop if args[-1] && args[-1].kind_of?(Hash)
        options ||= { }

        # Clean up the name
        name = FlexColumns::Definition::FieldDefinition.normalize_name(name)

        # Create a new field
        field = FlexColumns::Definition::FieldDefinition.new(@flex_column_class, name, args, options)

        # If we have a duplicate name, that's OK; we intentionally replace the existing field. But if we have a
        # collision in the JSON storage name, and the field names are different, we want to raise an exception,
        # because that means you actually have two _different_ fields with the same JSON storage name.
        same_json_storage_name_field = fields_by_json_storage_names[field.json_storage_name]
        if same_json_storage_name_field && same_json_storage_name_field.field_name != field.field_name
          raise FlexColumns::Errors::ConflictingJsonStorageNameError.new(@flex_column_class.model_class,
            @flex_column_class.column_name, name, same_json_storage_name_field.field_name, field.json_storage_name)
        end

        fields[name] = field
        fields_by_json_storage_names[field.json_storage_name] = field
      end

      # Adds all delegated methods to both the +column_dynamic_methods_module+, which should be included into the
      # flex-column contents class, and the +model_dynamic_methods_module+, which should be included into the
      # +model_class+. The +model_class+ itself is also passed here; this is used in the FieldDefinition just to make
      # sure we don't define methods that collide with column names or other method names on the model class itself.
      def add_delegated_methods!(column_dynamic_methods_module, model_dynamic_methods_module, model_class)
        each_field do |field_definition|
          field_definition.add_methods_to_flex_column_class!(column_dynamic_methods_module)
          field_definition.add_methods_to_model_class!(model_dynamic_methods_module, model_class)
        end
      end

      # Returns the names of all defined fields, in no particular order.
      def all_field_names
        fields.keys
      end

      # Adds delegated methods, as appropriate for IncludeFlexColumns#include_flex_columns_from, to the given
      # DynamicMethodsModule. +association_name+ is the name of the method on the target class that, when called, will
      # return the associated model object of the class on which this flex column is defined (_i.e._, the association
      # name); +target_class+ is the class into which the DynamicMethodsModule is included, so we can check to make sure
      # we're not clobbering methods that we really shouldn't clobber, and +options+ is any options passed along.
      def include_fields_into(dynamic_methods_module, association_name, target_class, options)
        each_field do |field_definition|
          field_definition.add_methods_to_included_class!(dynamic_methods_module, association_name, target_class, options)
        end
      end

      # Returns the field with the given name, or +nil+ if there is no such field
      def field_named(field_name)
        fields[FlexColumns::Definition::FieldDefinition.normalize_name(field_name)]
      end

      # Returns the field with the given JSON storage name, or +nil+ if there is no such field.
      def field_with_json_storage_name(json_storage_name)
        fields_by_json_storage_names[FlexColumns::Definition::FieldDefinition.normalize_name(json_storage_name)]
      end

      private
      attr_reader :fields, :fields_by_json_storage_names

      def each_field(&block)
        fields.each { |name, field| block.call(field) }
      end
    end
  end
end
