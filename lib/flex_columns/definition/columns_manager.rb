require 'flex_columns/definition/column_definition'
require 'flex_columns/dynamic_methods_module'

module FlexColumns
  module Definition
    class ColumnsManager
      attr_reader :model_class

      def initialize(model_class)
        @model_class = model_class
        @column_definitions = { }

        sync_methods!
      end

      def flex_column(flex_column_name, options, &block)
        new_definition = FlexColumns::Definition::ColumnDefinition.new(self, flex_column_name, options, &block)
        column_definitions[new_definition.flex_column_name] = new_definition

        sync_methods!
      end

      def all_column_definitions
        column_definitions.values
      end

      def column_definition(flex_column_name)
        flex_column_name = FlexColumns::Definition::ColumnDefinition.normalize_name(flex_column_name)
        column_definitions[flex_column_name] || raise("No flex column '#{flex_column_name}' on #{model_class.inspect}")
      end

      def define_direct_method_on_model_class!(method_name, &block)
        method_name = method_name.to_s.strip.downcase
        direct_methods_defined << method_name unless direct_methods_defined.include?(method_name)

        model_class.send(:define_method, method_name, &block)
      end

      def define_dynamic_method_on_model_class!(method_name, &block)
        methods_module.define_method(method_name, &block)
      end

      private
      attr_reader :direct_methods_defined
      attr_accessor :methods_module, :dynamic_methods_defined, :column_definitions

      def sync_methods!
        unless methods_module
          self.methods_module = FlexColumns::DynamicMethodsModule.new(model_class, :FlexColumnsDynamicMethods) do
            def flex_columns_manager
              fcm
            end

            def column_definition(flex_column_name)
              flex_columns_manager.column_definition(flex_column_name)
            end
          end
        end

        methods_module.remove_all_methods!

        @direct_methods_defined ||= [ ]
        direct_methods_defined.each do |method_name|
          @model_class.class_eval("remove_method :#{method_name}")
        end

        column_definitions.values.each { |cd| cd.define_methods! }
      end
    end
  end
end
