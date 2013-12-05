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

        if should_define_methods_on_model_class?
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

      def should_define_methods_on_model_class?
        ! (options.has_key?(:delegate) && (! options[:delegate]))
      end

      def name_for_delegated_method
        prefix = options[:delegate][:prefix] if options[:delegate].kind_of?(Hash)

        if prefix
          "#{prefix}_#{name}"
        else
          name
        end
      end

      def validate_options!
        options.assert_valid_keys(:delegate)

        if options[:delegate] && (options[:delegate] != true)
          if (! options[:delegate].kind_of?(Hash))
            raise ArgumentError, "Argument to :delegate must be true/false/nil, or a Hash"
          else
            options[:delegate].assert_valid_keys(:prefix)
          end
        end
      end
    end
  end
end
