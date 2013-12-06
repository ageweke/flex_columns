module FlexColumns
  class FieldDefinition
    class << self
      def normalize_name(name)
        case name
        when Symbol then name
        when String then
          raise "You must supply a non-empty String, not: #{name.inspect}" if name.strip.length == 0
          name.strip.downcase.to_sym
        else raise ArgumentError, "You must supply a name, not: #{name.inspect}"
        end
      end
    end

    attr_reader :field_name

    def initialize(flex_column_class, field_name, options = { })
      unless flex_column_class.respond_to?(:is_flex_column_class?) && flex_column_class.is_flex_column_class?
        raise ArgumentError, "You can't define a flex-column field against #{flex_column_class.inspect}; that isn't a flex-column class."
      end

      validate_options(options)

      @flex_column_class = flex_column_class
      @field_name = self.class.normalize_name(field_name)
      @options = options
    end

    def add_methods_to_flex_column_class!(dynamic_methods_module)
      mn = method_name
      return if (! mn)

      dynamic_methods_module.define_method(mn) do
        self[fn]
      end

      unless read_only?
        dynamic_methods_module.define_method("#{mn}=") do |x|
          self[fn] = x
        end
      end

      if private?
        dynamic_methods_module.private(mn)
        dynamic_methods_module.private("#{mn}=") unless read_only?
      end
    end

    def add_methods_to_model_class!(dynamic_methods_module)
      mn = method_name
      return if (! mn)

      fcc = flex_column_class

      dynamic_methods_module.define_method(mn) do
        flex_instance = fcc.object_for(self)
        flex_instance[fn]
      end

      unless read_only?
        dynamic_methods_module.define_method("#{mn}=") do |x|
          flex_instance = fcc.object_for(self)
          flex_instance[fn] = x
        end
      end

      if private?
        dynamic_methods_module.private(mn)
        dynamic_methods_module.private("#{mn}=") unless read_only?
      end
    end

    private
    attr_reader :flex_column_class, :options

    def validate_options(options)
      options.assert_valid_keys(:delegate, :private, :read_only)

      case options[:delegate]
      when nil then nil
      when true then nil
      when false then nil
      when Hash then options[:delegate].assert_valid_keys(:prefix)
      else raise "Invalid value for :delegate: #{options[:delegate].inspect}"
      end

      case options[:private]
      when true then nil
      when false then nil
      when nil then nil
      else raise "Invalid value for :private: #{options[:private].inspect}"
      end

      case options[:read_only]
      when true then nil
      when false then nil
      when nil then nil
      else raise "Invalid value for :read_only: #{options[:read_only].inspect}"
      end
    end

    def read_only?
      true if options[:read_only]
    end

    def delegate?
      true unless options.has_key?(:delegate) && (! options[:delegate])
    end

    def private?
      true if options[:private]
    end

    def method_name
      return nil if (! delegate?)

      if options[:delegate] && options[:delegate].kind_of?(Hash) && options[:delegate][:prefix]
        "#{options[:delegate][:prefix]}_#{field_name}"
      else
        field_name
      end
    end
  end
end
