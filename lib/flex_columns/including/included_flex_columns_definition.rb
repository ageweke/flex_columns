module FlexColumns
  module Including
    class IncludedFlexColumnsDefinition
      def initialize(delegating_class)
        unless delegating_class.kind_of?(Class)
          raise ArgumentError, "Delegating class must be a Class, not: #{delegating_class.inspect}"
        end

        @delegating_class = delegating_class
        @includes = { }
      end

      def include_flex_columns_from(association_name, options = { })
        association_name = association_name.to_sym
        association = association_for(association_name, options)

        includes[association_name] = options

        sync_delegations!
      end

      private
      attr_reader :delegating_class, :includes, :dynamic_methods_module

      def sync_delegations!
        @dynamic_methods_module ||= FlexColumns::DynamicMethodsModule.new(delegating_class, :IncludedFlexColumnsDynamicMethods)

        dynamic_methods_module.remove_all_methods!

        includes.each do |association_name, options|
          association = association_for(association_name, options)

          association.klass._flex_columns_manager.all_column_definitions.each do |column_definition|
            fcn = column_definition.flex_column_name

            dynamic_methods_module.define_method(fcn) do
              associated_model = send(association_name) || send("build_#{association_name}")
              associated_model.send(fcn)
            end

            column_definition.all_fields.each do |field_definition|
              fdn = field_definition.name

              dynamic_methods_module.define_method(fdn) do
                flex_contents = send(fcn)
                flex_contents.send(fdn)
              end

              dynamic_methods_module.define_method("#{fdn}=") do |x|
                flex_contents = send(fcn)
                raise "no flex contents for #{fdn.inspect}?" unless flex_contents
                flex_contents.send("#{fdn}=", x)
              end
            end
          end
        end
      end

      def association_for(association_name, options)
        association = delegating_class.reflect_on_association(association_name.to_sym)
        unless association
          delegating_class.has_one(association_name, options)
          association = delegating_class.reflect_on_association(association_name.to_sym)
        end

        unless association.macro == :has_one
          raise ArgumentError, %{You're trying to include_flex_columns_from in class #{delegating_class.name}, using the association
named #{association.name.inspect}. However, that association is of type #{association.macro.inspect},
not :has_one. We can only include flex columns from has_one associations, because otherwise
there's no way to know which associated record the data would come from.}
        end

        other_class = association.klass
        unless other_class.respond_to?(:has_any_flex_columns?) && other_class.has_any_flex_columns?
          raise ArgumentError, "You tried to include flex columns from class #{other_class.name} into #{delegating_class.name}, but #{other_class.name} has no flex columns."
        end

        association
      end
    end
  end
end
