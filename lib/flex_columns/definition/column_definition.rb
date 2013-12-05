require 'active_support'
require 'active_support/core_ext'
require 'flex_columns/definition/field_definition'

module FlexColumns
  module Definition
    class ColumnDefinition
      class << self
        def normalize_name(name)
          case name
          when Symbol then name
          when String then name.strip.downcase.to_sym
          else raise ArgumentError, "You must supply a name, not: #{name.inspect}"
          end
        end
      end

      attr_reader :flex_column_name

      def initialize(columns_manager, flex_column_name, options, &block)
        @columns_manager = columns_manager
        @flex_column_name = self.class.normalize_name(flex_column_name)
        @options = options
        @has_validations = false

        @fields = { }

        validate_options!

        instance_eval(&block)
      end

      delegate :define_dynamic_method_on_model_class!, :to => :columns_manager

      def field_delegation_setting
        @field_delegation_setting ||= begin
          if options.has_key?(:delegate) && (! options[:delegate])
            :no
          elsif options[:delegate] && options[:delegate].kind_of?(Hash) && options[:delegate][:prefix]
            options[:delegate][:prefix]
          else
            :yes
          end
        end
      end

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

        fields.values.each { |field| field.define_methods_on_model_class! }
      end

      def contents_class
        @contents_class ||= begin
          out = Class.new(FlexColumns::Contents::BaseContents)
          name = "#{flex_column_name.to_s.camelize}FlexContents".to_sym
          model_class.const_set(name, out)
        end
      end

      def field(name, *args)
        field_definition = FlexColumns::Definition::FieldDefinition.new(self, name, *args)
        field_definition.define_methods_on_flex_column!

        fields[field_definition.name] = field_definition
      end

      private
      attr_reader :columns_manager, :fields, :has_validations, :options

      def field_named(name)
        fields[FlexColumns::Definition::FieldDefinition.normalize_name(name)]
      end

      def model_class
        columns_manager.model_class
      end

      def validate_options!
        options.assert_valid_keys(:delegate)

        if options[:delegate] && (options[:delegate] != true)
          if (! options[:delegate].kind_of?(Hash))
            raise ArgumentError, "Argument to :delegate must be true/false/nil, or a Hash"
          else
            options[:delegate].assert_valid_keys(:prefix)
            prefix = options[:delegate][:prefix]
            raise ArgumentError, "Prefix must be a String, not #{prefix.inspect}" unless prefix.kind_of?(String) && prefix.strip.length > 0
          end
        end
      end
    end
  end
end
