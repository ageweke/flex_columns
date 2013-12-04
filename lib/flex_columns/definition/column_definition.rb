require 'active_support'
require 'active_support/core_ext'

module FlexColumns
  module Definition
    class ColumnDefinition
      attr_reader :flex_column_name

      def initialize(columns_manager, flex_column_name, options, &block)
        @columns_manager = columns_manager
        @flex_column_name = flex_column_name.to_s.strip.downcase
        @options = options
        @has_validations = false

        @fields = { }

        instance_eval(&block)
      end

      def has_validations?
        !! has_validations
      end

      def validates(*args, &block)
        @has_validations = true
        contents_class.validates(*args, &block)
      end

      def has_field?(field_name)
        fields[field_name.to_s.strip.downcase]
      end

      def define_methods!
        fcn = flex_column_name

        columns_manager.define_direct_method!(flex_column_name) do
          _flex_columns_contents_manager.contents_for(fcn)
        end

        fields.keys.each do |field_name|
          columns_manager.define_dynamic_method!(field_name) do
            contents = send(fcn)
            contents.send(field_name)
          end

          columns_manager.define_dynamic_method!("#{field_name}=") do |x|
            contents = send(fcn)
            contents.send("#{field_name}=", x)
          end
        end
      end

      def contents_class
        @contents_class ||= begin
          out = Class.new(FlexColumns::Contents::BaseContents)
          name = "#{flex_column_name.camelize}FlexContents".to_sym
          model_class.const_set(name, out)
        end
      end

      def field(name)
        name = name.to_s.strip.downcase
        fields[name] = true

        contents_class.send(:define_method, name) do
          self[name]
        end

        contents_class.send(:define_method, "#{name}=") do |x|
          self[name] = x
        end
      end

      private
      attr_reader :columns_manager, :fields, :has_validations

      def model_class
        columns_manager.model_class
      end
    end
  end
end
