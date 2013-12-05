require 'active_support'

module FlexColumns
  module IncludeFlexColumns
    extend ::ActiveSupport::Concern

    module ClassMethods
      def include_flex_columns_from(association_name, options = { })
        association = reflect_on_association(association_name.to_sym)
        unless association
          has_one association_name, options
          association = reflect_on_association(association_name.to_sym)
        end

        unless association.macro == :has_one
          raise ArgumentError, %{You're trying to include_flex_columns_from in class #{self.name}, using the association
named #{association.name.inspect}. However, that association is of type #{association.macro.inspect},
not :has_one. We can only include flex columns from has_one associations, because otherwise
there's no way to know which associated record the data would come from.}
        end

        other_class = association.klass
        unless other_class.respond_to?(:has_any_flex_columns?) && other_class.has_any_flex_columns?
          raise ArgumentError, "You tried to include flex columns from class #{other_class.name} into #{self.name}, but #{other_class.name} has no flex columns."
        end

        other_class._flex_columns_manager.create_delegations_from(self, association_name)
      end
    end
  end
end
