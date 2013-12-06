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
      fn = field_name

      dynamic_methods_module.define_method(fn) do
        self[fn]
      end

      dynamic_methods_module.define_method("#{fn}=") do |x|
        self[fn] = x
      end

      if private?
        dynamic_methods_module.private(fn)
        dynamic_methods_module.private("#{fn}=")
      end
    end

    def add_methods_to_model_class!(dynamic_methods_module)
      return if (! flex_column_class.delegation_type)

      mn = field_name
      mn = "#{flex_column_class.delegation_prefix}_#{mn}" if flex_column_class.delegation_prefix

      fcc = flex_column_class
      fn = field_name

      dynamic_methods_module.define_method(mn) do
        flex_instance = fcc.object_for(self)
        flex_instance[fn]
      end

      dynamic_methods_module.define_method("#{mn}=") do |x|
        flex_instance = fcc.object_for(self)
        flex_instance[fn] = x
      end

      if private? || flex_column_class.delegation_type == :private
        dynamic_methods_module.private(mn)
        dynamic_methods_module.private("#{mn}=")
      end
    end

    def add_methods_to_included_class!(dynamic_methods_module, association_name, options)
      return if (! flex_column_class.delegation_type)

      prefix = options[:prefix] || flex_column_class.delegation_prefix
      is_private = private? || (flex_column_class.delegation_type == :private) || (options[:visibility] == :private)

      if is_private && options[:visibility] == :public
        raise ArgumentError, %{You asked for public visibility for methods included from association #{association_name.inspect},
but the flex column #{flex_column_class.model_class.name}.#{flex_column_class.column_name} has its methods
defined with private visibility (either in the flex column itself, or at the model level).

You can't have methods be 'more public' in the included class than they are in the class
they're being included from.}
      end

      mn = field_name
      mn = "#{prefix}_#{mn}" if prefix

      fcc = flex_column_class
      fn = field_name

      dynamic_methods_module.define_method(mn) do
        associated_object = send(association_name) || send("build_#{association_name}")
        flex_column_object = associated_object.send(fcc.column_name)
        flex_column_object.send(fn)
      end

      dynamic_methods_module.define_method("#{mn}=") do |x|
        associated_object = send(association_name) || send("build_#{association_name}")
        flex_column_object = associated_object.send(fcc.column_name)
        flex_column_object.send("#{fn}=", x)
      end

      if is_private
        dynamic_methods_module.private(mn)
        dynamic_methods_module.private("#{mn}=")
      end
    end

    private
    attr_reader :flex_column_class, :options

    def validate_options(options)
      options.assert_valid_keys(:visibility)

      case options[:visibility]
      when nil then nil
      when :public then nil
      when :private then nil
      else raise ArgumentError, "Invalid value for :visibility: #{options[:visibility].inspect}"
      end
    end

    def private?
      case options[:visibility]
      when :public then false
      when :private then true
      when nil then flex_column_class.fields_are_private_by_default?
      else raise "This should never happen: #{options[:visibility].inspect}"
      end
    end
  end
end
