require 'flex_columns/errors'
require 'flex_columns/definition/field_definition'

module FlexColumns
  module Definition
    class FieldSet
      def initialize(flex_column_class)
        @flex_column_class = flex_column_class
        @fields = { }
        @fields_by_json_storage_names = { }
      end

      def field(name, *args)
        options = args.pop if args[-1] && args[-1].kind_of?(Hash)
        options ||= { }

        name = FlexColumns::Definition::FieldDefinition.normalize_name(name)

        field = FlexColumns::Definition::FieldDefinition.new(@flex_column_class, name, args, options)
        same_json_storage_name_field = fields_by_json_storage_names[field.json_storage_name]
        if same_json_storage_name_field && same_json_storage_name_field.field_name != field.field_name
          raise FlexColumns::Errors::ConflictingJsonStorageNameError.new(model_class, column_name, name, same_json_storage_name_field.field_name, field.json_storage_name)
        end

        fields[name] = field
        fields_by_json_storage_names[field.json_storage_name] = field
      end

      def add_delegated_methods!(column_dynamic_methods_module, model_dynamic_methods_module)
        each_field do |field_definition|
          field_definition.add_methods_to_flex_column_class!(column_dynamic_methods_module)
          field_definition.add_methods_to_model_class!(model_dynamic_methods_module)
        end
      end

      def all_field_names
        fields.keys
      end

      def include_fields_into(dynamic_methods_module, association_name, options)
        each_field do |field_definition|
          field_definition.add_methods_to_included_class!(dynamic_methods_module, association_name, options)
        end
      end

      def field_named(field_name)
        fields[FlexColumns::Definition::FieldDefinition.normalize_name(field_name)]
      end

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
