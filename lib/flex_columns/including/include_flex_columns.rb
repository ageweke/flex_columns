require 'active_support/concern'

module FlexColumns
  module Including
    module IncludeFlexColumns
      extend ActiveSupport::Concern

      module ClassMethods
        def _flex_columns_include_flex_columns_dynamic_methods_module
          @_flex_columns_include_flex_columns_dynamic_methods_module ||= FlexColumns::Util::DynamicMethodsModule.new(self, :FlexColumnsIncludedColumnsMethods)
        end

        def include_flex_columns_from(*args, &block)
          options = args.pop if args[-1] && args[-1].kind_of?(Hash)
          options ||= { }

          options.assert_valid_keys(:prefix, :visibility, :delegate)

          case options[:prefix]
          when nil, String, Symbol then nil
          else raise ArgumentError, "Invalid value for :prefix: #{options[:prefix].inspect}"
          end

          unless [ :public, :private, nil ].include?(options[:visibility])
            raise ArgumentError, "Invalid value for :visibility: #{options[:visibility].inspect}"
          end

          unless [ true, false, nil ].include?(options[:delegate])
            raise ArgumentError, "Invalid value for :delegate: #{options[:delegate].inspect}"
          end

          association_names = args

          association_names.each do |association_name|
            association = reflect_on_association(association_name.to_sym)
            unless association
              raise ArgumentError, %{You asked #{self.name} to include flex columns from association #{association_name.inspect},
  but this class doesn't seem to have such an association. Associations it has are:

    #{reflect_on_all_associations.map(&:name).sort_by(&:to_s).join(", ")}}
            end

            unless [ :has_one, :belongs_to ].include?(association.macro)
              raise ArgumentError, %{You asked #{self.name} to include flex columns from association #{association_name.inspect},
  but that association is of type #{association.macro.inspect}, not :has_one or :belongs_to.

  We can only include flex columns from an association of these types, because otherwise
  there is no way to know which target object to include the data from.}
            end

            target_class = association.klass
            if (! target_class.respond_to?(:has_any_flex_columns?)) || (! target_class.has_any_flex_columns?)
              raise ArgumentError, %{You asked #{self.name} to include flex columns from association #{association_name.inspect},
  but the target class of that association, #{association.klass.name}, has no flex columns defined.}
            end

            target_class._all_flex_column_names.each do |flex_column_name|
              flex_column_class = target_class._flex_column_class_for(flex_column_name)
              flex_column_class.include_fields_into(_flex_columns_include_flex_columns_dynamic_methods_module, association_name, options)
            end
          end
        end
      end
    end
  end
end
