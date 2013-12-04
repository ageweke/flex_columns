require 'flex_columns/contents/base_contents'

module FlexColumns
  module Contents
    class ContentsManager
      def initialize(model_instance)
        @model_instance = model_instance
        @contents = { }
      end

      def contents_for(flex_column_name)
        definition = columns_manager.column_definition(flex_column_name) # so it'll raise if not present
        contents[flex_column_name] ||= FlexColumns::Contents::BaseContents.new(model_instance, definition)
      end

      def serialize!
        @contents.each do |flex_column_name, contents|
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
