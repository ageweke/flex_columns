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
        association = association_for(association_name)

        validate_options(options, association)

        includes[association_name] = options

        sync_delegations!
      end

      private
      attr_reader :delegating_class, :includes, :dynamic_methods_module

      def sync_delegations!
        @dynamic_methods_module ||= FlexColumns::DynamicMethodsModule.new(delegating_class, :IncludedFlexColumnsDynamicMethods)
        dynamic_methods_module.remove_all_methods!

        includes.each do |association_name, options|
          association = association_for(association_name)

          association.klass._flex_columns_manager.all_column_definitions.each do |column_definition|
            unless options[:columns] && (! options[:columns].include?(column_definition.flex_column_name))
              define_methods_for_flex_column(association_name, column_definition, options)
            end
          end
        end
      end

      def define_methods_for_flex_column(association_name, column_definition, options)
        prefix = options[:prefix]

        fcn = column_definition.flex_column_name

        flex_column_method_name = fcn.to_s
        flex_column_method_name = "#{prefix}_#{fcn}" if prefix

        dynamic_methods_module.define_method(flex_column_method_name) do
          associated_model = send(association_name) || send("build_#{association_name}")
          associated_model.send(fcn)
        end

        column_definition.all_fields.each do |field_definition|
          fdn = field_definition.name

          flex_column_field_name = fdn.to_s
          flex_column_field_name = "#{prefix}_#{flex_column_field_name}" if prefix

          dynamic_methods_module.define_method(flex_column_field_name) do
            flex_contents = send(flex_column_method_name)
            flex_contents.send(fdn)
          end

          dynamic_methods_module.define_method("#{flex_column_field_name}=") do |x|
            flex_contents = send(flex_column_method_name)
            raise "no flex contents for #{fdn.inspect}?" unless flex_contents
            flex_contents.send("#{fdn}=", x)
          end
        end
      end

      def validate_options(options, association)
        options.assert_valid_keys(:columns, :prefix)

        columns = options[:columns]
        if columns
          unless columns.kind_of?(Symbol) || columns.kind_of?(Array)
            raise ArgumentError, "If you specify :columns, it must be an Array or a Symbol, not: #{columns.inspect}"
          end

          options[:columns] = Array(columns)
        end

        prefix = options[:prefix]
        if prefix
          unless (prefix.kind_of?(String) || prefix.kind_of?(Symbol)) && (prefix.to_s.length > 0)
            raise ArgumentError, "Prefix must be a String or Symbol, not: #{prefix.inspect}"
          end

          options[:prefix] = options[:prefix].to_s
        end
      end

      def association_for(association_name)
        association = delegating_class.reflect_on_association(association_name.to_sym)
        unless association
          raise %{You're trying to include_flex_columns_from in class #{delegating_class.name}, using the association
named #{association_name.inspect}. However, there is no such association.

You need to define an association (using has_one) before you can automatically include
flex columns from the target class.}
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
