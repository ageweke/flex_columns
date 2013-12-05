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

    def initialize(flex_column_class, field_name, options = { })
      unless flex_column_class.respond_to?(:is_flex_column_class?) && flex_column_class.is_flex_column_class?
        raise ArgumentError, "You can't define a flex-column field against #{flex_column_class.inspect}; that isn't a flex-column class."
      end

      @flex_column_class = flex_column_class
      @field_name = self.class.normalize_name(field_name)
      @options = options
    end

    def add_methods_to_flex_column_class!(dynamic_methods_module)
      fn = @field_name

      dynamic_methods_module.define_method(fn) do
        self[fn]
      end

      dynamic_methods_module.define_method("#{fn}=") do |x|
        self[fn] = x
      end
    end

    def add_methods_to_model_class!(dynamic_methods_module)
      fn = @field_name
      fcc = flex_column_class

      dynamic_methods_module.define_method(fn) do
        flex_instance = fcc.object_for(self)
        flex_instance[fn]
      end

      dynamic_methods_module.define_method("#{fn}=") do |x|
        flex_instance = fcc.object_for(self)
        flex_instance[fn] = x
      end
    end

    private
    attr_reader :flex_column_class
  end
end
