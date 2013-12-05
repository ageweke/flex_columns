require 'flex_columns/contents/base_contents'

module FlexColumns
  module Contents
    class ContentsManager
      def initialize(model_instance)
        @model_instance = model_instance
        @contents = { }
      end

      def contents_for(flex_column_name)
        flex_column_name = FlexColumns::Definition::ColumnDefinition.normalize_name(flex_column_name)
        definition = columns_manager.column_definition(flex_column_name) # so it'll raise if not present
        contents[flex_column_name] ||= definition.contents_class.new(model_instance, definition)
      end

      def before_validation!
        validate!
      end

      def before_save!
        serialize!
      end

      def validate!
        columns_manager.all_column_definitions.each do |column_definition|
          if column_definition.has_validations?
            contents = contents_for(column_definition.flex_column_name)

            unless contents.valid?
              contents.errors.each do |name, message|
                model_instance.errors.add("#{column_definition.flex_column_name}.#{name}", message)
              end
            end
          end
        end
      end

      def serialize!
        contents.each do |flex_column_name, contents|
          contents.serialize!
        end
      end

      private
      attr_reader :model_instance, :contents

      def columns_manager
        @model_instance.class._flex_columns_manager
      end
    end
  end
end
