module FlexColumns
  module Definition
    class FieldDefinition
      class << self
        def normalize_name(name)
          case name
          when Symbol then name
          when String then name.strip.downcase.to_sym
          else raise ArgumentError, "You must supply a name, not: #{name.inspect}"
          end
        end
      end

      attr_reader :name

      def initialize(column_definition, field_name, *args)
        @column_definition = column_definition
        @name = self.class.normalize_name(field_name)
        @options = if args[-1] && args[-1].kind_of?(Hash) then args.pop else { } end

        validate_options!

        raise ArgumentError, "Unexpected arguments: #{args.inspect}" if args.length > 0
      end

      def define_methods_on_flex_column!
        field_name = name

        column_definition.define_flex_column_method!(field_name) do
          self[field_name]
        end

        column_definition.define_flex_column_method!("#{field_name}=") do |x|
          self[field_name] = x
        end
      end

      def define_methods_on_model_class!
        field_name = name
        flex_column_name = column_definition.flex_column_name

        delegation_setting = effective_field_delegation_setting
        if delegation_setting != :no
          name_for_delegated_method = field_name
          name_for_delegated_method = "#{delegation_setting}_#{name_for_delegated_method}" if delegation_setting.kind_of?(String)

          column_definition.define_dynamic_method_on_model_class!(name_for_delegated_method) do
            contents = send(flex_column_name)
            contents.send(field_name)
          end

          column_definition.define_dynamic_method_on_model_class!("#{name_for_delegated_method}=") do |x|
            contents = send(flex_column_name)
            contents.send("#{field_name}=", x)
          end
        end
      end

      private
      attr_reader :column_definition, :options

      def our_field_delegation_setting
        @our_field_delegation_setting ||= begin
          if options.has_key?(:delegate) && (! options[:delegate])
            :no
          elsif options[:delegate] && options[:delegate].kind_of?(Hash) && options[:delegate][:prefix]
            options[:delegate][:prefix]
          elsif options[:delegate] && options[:delegate]
            :yes
          else
            nil
          end
        end
      end

      def effective_field_delegation_setting
        our_field_delegation_setting || column_definition.field_delegation_setting
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
