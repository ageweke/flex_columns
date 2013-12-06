require 'active_record'
require 'active_support/concern'
require 'flex_columns/has_flex_columns'

module FlexColumns
  module ActiveRecord
    module Base
      extend ActiveSupport::Concern

      module ClassMethods
        def has_any_flex_columns?
          false
        end

        def flex_column(*args, &block)
          include FlexColumns::HasFlexColumns
          flex_column(*args, &block)
        end
      end
    end
  end
end
