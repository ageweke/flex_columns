require 'active_record'
require 'active_support/concern'
require 'flex_columns/contents/contents_manager'
require 'flex_columns/definition/columns_manager'

module FlexColumns
  module HasFlexColumns
    extend ActiveSupport::Concern

    included do
      before_validation :flex_columns_before_validation!
      before_save :flex_columns_before_save!
    end

    def _flex_columns_contents_manager
      @_flex_columns_contents_manager ||= FlexColumns::Contents::ContentsManager.new(self)
    end

    def flex_columns_before_save!
      _flex_columns_contents_manager.before_save!
    end

    def flex_columns_before_validation!
      _flex_columns_contents_manager.before_validation!
    end

    module ClassMethods
      def has_any_flex_columns?
        true
      end

      def flex_column(flex_column_name, options = { }, &block)
        _flex_columns_manager.flex_column(flex_column_name, options, &block)
      end

      def _flex_columns_manager
        @_flex_columns_manager ||= FlexColumns::Definition::ColumnsManager.new(self)
      end
    end
  end
end
