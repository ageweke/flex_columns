require 'active_support'
require 'flex_columns/including/included_flex_columns_definition'

module FlexColumns
  module IncludeFlexColumns
    extend ::ActiveSupport::Concern

    module ClassMethods
      def _included_flex_columns_definition
        @_included_flex_columns_definition ||= FlexColumns::Including::IncludedFlexColumnsDefinition.new(self)
      end

      delegate :include_flex_columns_from, :include_flex_column_from, :to => :_included_flex_columns_definition
    end
  end
end
