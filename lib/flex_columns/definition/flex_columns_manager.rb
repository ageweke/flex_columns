require 'flex_columns/definition/column_definition'

module FlexColumns
  module Definition
    class ColumnsManager
      def initialize(model_class)
        @model_class = model_class
        @column_definitions = [ ]

        sync_methods!
      end

      def flex_column(flex_column_name, options, &block)
        new_definition = FlexColumns::Definition::ColumnDefinition.new(self, flex_column_name, options, &block)
        @column_definitions.delete_if { |cd| cd.flex_column_name == new_definition.flex_column_name }
        @column_definitions << new_definition

        sync_methods!
      end

      def column_definition(flex_column_name)
        flex_column_name = flex_column_name.to_s.strip.downcase
        out = @column_definitions.detect { |cd| cd.flex_column_name == flex_column_name }
        out || raise("No flex column '#{flex_column_name}' on #{model_class.inspect}")
      end

      def define_direct_method!(method_name, &block)
        method_name = method_name.to_s.strip.downcase
        direct_methods_defined << method_name unless direct_methods_defined.include?(method_name)

        $stderr.puts "Defining direct method: #{method_name.inspect}"

        model_class.send(:define_method, method_name, &block)
      end

      def define_dynamic_method!(method_name, &block)
        method_name = method_name.to_s.strip.downcase
        self.dynamic_methods_defined << method_name unless dynamic_methods_defined.include?(method_name)

        $stderr.puts "Defining dynamic method: #{method_name.inspect}"

        methods_module.send(:define_method, method_name, &block)
      end

      private
      attr_reader :model_class, :direct_methods_defined
      attr_accessor :methods_module, :dynamic_methods_defined, :column_definitions

      def sync_methods!
        unless methods_module
          fcm = self
          self.methods_module = Module.new do
            def flex_columns_manager
              fcm
            end

            def column_definition(flex_column_name)
              flex_columns_manager.column_definition(flex_column_name)
            end
          end

          model_class.const_set(:FlexColumnsDynamicMethods, methods_module)
          model_class.send(:include, methods_module)

          self.dynamic_methods_defined = [ ]
        end

        @direct_methods_defined ||= [ ]

        dynamic_methods_defined.each do |method_name|
          methods_module.module_eval("remove_method :#{method_name}")
        end

        direct_methods_defined.each do |method_name|
          @model_class.class_eval("remove_method :#{method_name}")
        end

        column_definitions.each { |cd| cd.define_methods! }
      end
    end
  end
end
