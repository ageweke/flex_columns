require 'active_record'
require 'active_support/concern'
require 'flex_columns/contents/contents_manager'
require 'flex_columns/definition/flex_columns_manager'

module FlexColumns
  module HasFlexColumns
    extend ActiveSupport::Concern

    def _flex_columns_contents_manager
      @_flex_columns_contents_manager ||= FlexColumns::Contents::ContentsManager.new(self)
    end

    module ClassMethods
      def flex_column(flex_column_name, options = { }, &block)
        _flex_columns_manager.flex_column(flex_column_name, options, &block)
      end

      def _flex_columns_manager
        @_flex_columns_manager ||= FlexColumns::Definition::ColumnsManager.new(self)
      end
    end
  end
end
