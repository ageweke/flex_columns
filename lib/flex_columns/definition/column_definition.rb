require 'active_support'
require 'active_support/core_ext'
require 'flex_columns/definition/field_definition'

module FlexColumns
  module Definition
    class ColumnDefinition
      attr_reader :flex_column_name

      def initialize(columns_manager, flex_column_name, options, &block)
        @columns_manager = columns_manager
        @flex_column_name = flex_column_name.to_s.strip.downcase
        @options = options
        @has_validations = false

        @fields = [ ]

        instance_eval(&block)
      end

      delegate :define_dynamic_method_on_model_class!, :to => :columns_manager

      def define_flex_column_method!(*args, &block)
        contents_class.send(:define_method, *args, &block)
      end

      def has_validations?
        !! has_validations
      end

      def validates(*args, &block)
        @has_validations = true
        contents_class.validates(*args, &block)
      end

      def has_field?(field_name)
        !! field_named(field_name)
      end

      def define_methods!
        fcn = flex_column_name
        columns_manager.define_direct_method_on_model_class!(flex_column_name) do
          _flex_columns_contents_manager.contents_for(fcn)
        end

        fields.each { |field| field.define_methods_on_model_class! }
      end

      def contents_class
        @contents_class ||= begin
          out = Class.new(FlexColumns::Contents::BaseContents)
          name = "#{flex_column_name.camelize}FlexContents".to_sym
          model_class.const_set(name, out)
        end
      end

      def field(name, *args)
        field_definition = FlexColumns::Definition::FieldDefinition.new(self, name, *args)
        field_definition.define_methods_on_flex_column!

        fields << field_definition
      end

      private
      attr_reader :columns_manager, :fields, :has_validations

      def field_named(name)
        fields.detect { |f| f.name.to_s == name.to_s.strip.downcase }
      end

      def model_class
        columns_manager.model_class
      end
    end
  end
end
