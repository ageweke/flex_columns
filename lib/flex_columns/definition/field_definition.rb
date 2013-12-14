module FlexColumns
  module Definition
    # A FieldDefinition represents, well, the definition of a field. One of these objects is created for each field
    # you declare in a flex column. It keeps track of (at minimum) the name of the field; it also is responsible for
    # implementing our "shorthand types" system (where declaring your field as +:integer+ adds a validation that
    # requires it to be an integer, for example).
    #
    # Perhaps most significantly, a FieldDefinition object is responsible for creating the appropriate methods on
    # the flex-column class and on the model class, and also for adding methods to classes that have invoked
    # IncludeFlexColumns#include_flex_columns_from.
    class FieldDefinition
      class << self
        # Given the name of a field, returns a normalized version of that name -- so we can compare using +==+ without
        # worrying about String vs. Symbol and so on.
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

      # Creates a new instance. +flex_column_class+ is the Class we created for this flex column -- _i.e._, a class
      # that has said <tt>extend FlexColumns::Contents::FlexColumnContentsClass</tt>. +field_name+ is the name of the
      # field. +additional_arguments+ is an Array containing any additional arguments that were passed -- right now,
      # that can only be the type of the field (_e.g._, +:integer+, etc.). +options+ is any options that were passed;
      # this can contain:
      #
      # :visibility, :null, :enum, :limit, :json
      # [:visibility] Can be set to +:public+ or +:private+; will override the default visibility for fields specified
      #               on the flex-column class itself.
      # [:null] If present and set to +false+, a validation requiring data in this field will be added.
      # [:enum] If present, must be mapped to an Array; a validation requiring the data to be one of the elements of
      #         the array will be added.
      # [:limit] If present, must be mapped to an integer; a validation requiring the length of the data to be at most
      #          this value will be added.
      # [:json] If present, must be mapped to a String or Symbol; this specifies that the field should be stored under
      #         the given key in the JSON, rather than its field name.
      def initialize(flex_column_class, field_name, additional_arguments, options)
        unless flex_column_class.respond_to?(:is_flex_column_class?) && flex_column_class.is_flex_column_class?
          raise ArgumentError, "You can't define a flex-column field against #{flex_column_class.inspect}; that isn't a flex-column class."
        end

        validate_options(options)
        @flex_column_class = flex_column_class
        @field_name = self.class.normalize_name(field_name)
        @options = options
        @field_type = nil

        apply_additional_arguments(additional_arguments)
        apply_validations!
      end

      # Returns the key under which the field's value should be stored in the JSON.
      def json_storage_name
        (options[:json] || field_name).to_s.strip.downcase.to_sym
      end

      # Defines appropriate accessor methods for this field on the given DynamicMethodsModule, which should be included
      # in the flex-column class (not the model class). These are quite simple; they always exist (and should overwrite
      # any existing methods, since we're last-definition-wins). We just need to make them work, and make them private,
      # if needed.
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

      # Defines appropriate accessor methods for this field on the given DynamicMethodsModule, which should be included
      # in the model class. We also pass +model_class+ so that we can check to see if we're going to conflict with one
      # of its columns first, or other methods we shouldn't clobber.
      #
      # We need to respect visibility (public or private) of methods, and the delegation prefix assigned at the
      # flex-column level.
      def add_methods_to_model_class!(dynamic_methods_module, model_class)
        return if (! flex_column_class.delegation_type) # :delegate => false on the flex column means don't delegate from the model at all

        mn = field_name
        mn = "#{flex_column_class.delegation_prefix}_#{mn}".to_sym if flex_column_class.delegation_prefix

        if model_class._flex_columns_safe_to_define_method?(mn)
          fcc = flex_column_class
          fn = field_name

          should_be_private = (private? || flex_column_class.delegation_type == :private)

          dynamic_methods_module.define_method(mn) do
            flex_instance = fcc.object_for(self)
            flex_instance[fn]
          end
          dynamic_methods_module.private(mn) if should_be_private

          dynamic_methods_module.define_method("#{mn}=") do |x|
            flex_instance = fcc.object_for(self)
            flex_instance[fn] = x
          end
          dynamic_methods_module.private("#{mn}=") if should_be_private
        end
      end

      # Defines appropriate accessor methods for this field on the given DynamicMethodsModule, which should be included
      # in some target model class that has said +include_flex_columns_from+ on the clsas containing this field.
      # +association_name+ is the name of the association method name that, when called on the class that includes the
      # DynamicMethodsModule, will return an instance of the model class in which this field lives. +target_class+ is
      # the target class we're defining methods on, so that we can check if we're going to conflict with some method
      # there that we should not clobber.
      #
      # +options+ can contain:
      #
      # [:visibility] If +:private+, then methods will be defined as private.
      # [:prefix] If specified, then methods will be prefixed with the given prefix. This will override the prefix
      #           specified on the flex-column class, if any.
      def add_methods_to_included_class!(dynamic_methods_module, association_name, target_class, options)
        return if (! flex_column_class.delegation_type)

        prefix = if options.has_key?(:prefix) then options[:prefix] else flex_column_class.delegation_prefix end
        is_private = private? || (flex_column_class.delegation_type == :private) || (options[:visibility] == :private)

        if is_private && options[:visibility] == :public
          raise ArgumentError, %{You asked for public visibility for methods included from association #{association_name.inspect},
  but the flex column #{flex_column_class.model_class.name}.#{flex_column_class.column_name} has its methods
  defined with private visibility (either in the flex column itself, or at the model level).

  You can't have methods be 'more public' in the included class than they are in the class
  they're being included from.}
        end

        mn = field_name
        mn = "#{prefix}_#{mn}".to_sym if prefix

        fcc = flex_column_class
        fn = field_name

        if target_class._flex_columns_safe_to_define_method?(mn)
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
      end

      private
      attr_reader :flex_column_class, :options

      # Checks that the options passed into this class are correct. This is both so that we have good exceptions, and so
      # that we have them early -- it's much nicer if errors happen when you try to define your flex column, rather than
      # much later on, when it really matters, possibly in production.
      def validate_options(options)
        options.assert_valid_keys(:visibility, :null, :enum, :limit, :json)

        case options[:visibility]
        when nil then nil
        when :public then nil
        when :private then nil
        else raise ArgumentError, "Invalid value for :visibility: #{options[:visibility].inspect}"
        end

        case options[:json]
        when nil, String, Symbol then nil
        else raise ArgumentError, "Invalid value for :json: #{options[:json].inspect}"
        end

        unless [ nil, true, false ].include?(options[:null])
          raise ArgumentError, "Invalid value for :null: #{options[:null].inspect}"
        end
      end

      # Should we define private methods?
      def private?
        case options[:visibility]
        when :public then false
        when :private then true
        when nil then flex_column_class.fields_are_private_by_default?
        else raise "This should never happen: #{options[:visibility].inspect}"
        end
      end

      # Given any additional arguments after the name of the field (e.g., <tt>field :foo, :integer</tt>), apply them
      # as appropriate. Currently, the only kind of accepted additional argument is a type.
      def apply_additional_arguments(additional_arguments)
        type = additional_arguments.shift
        if type
          begin
            send("apply_validations_for_#{type}")
          rescue NoMethodError => nme
            raise ArgumentError, "Unknown type: #{type.inspect}"
          end
        end

        if additional_arguments.length > 0
          raise ArgumentError, "Invalid additional arguments: #{additional_arguments.inspect}"
        end
      end

      # Apply the correct validations for a field of type :integer. (Called from #apply_additional_arguments via
      # metaprogramming.)
      def apply_validations_for_integer
        flex_column_class.validates field_name, :numericality => { :only_integer => true }
      end

      # Apply the correct validations for a field of type :string. (Called from #apply_additional_arguments via
      # metaprogramming.)
      def apply_validations_for_string
        flex_column_class.validates_each field_name do |record, attr, value|
          record.errors.add(attr, "must be a String") if value && (! value.kind_of?(String)) && (! value.kind_of?(Symbol))
        end
      end

      # Apply the correct validations for a field of type :text. (Called from #apply_additional_arguments via
      # metaprogramming.)
      def apply_validations_for_text
        apply_validations_for_string
      end

      # Apply the correct validations for a field of type :float. (Called from #apply_additional_arguments via
      # metaprogramming.)
      def apply_validations_for_float
        flex_column_class.validates field_name, :numericality => true, :allow_nil => true
      end

      # Apply the correct validations for a field of type :decimal. (Called from #apply_additional_arguments via
      # metaprogramming.)
      def apply_validations_for_decimal
        apply_validations_for_float
      end

      # Apply the correct validations for a field of type :date. (Called from #apply_additional_arguments via
      # metaprogramming.)
      def apply_validations_for_date
        flex_column_class.validates_each field_name do |record, attr, value|
          record.errors.add(attr, "must be a Date") if value && (! value.kind_of?(Date))
        end
      end

      # Apply the correct validations for a field of type :time. (Called from #apply_additional_arguments via
      # metaprogramming.)
      def apply_validations_for_time
        flex_column_class.validates_each field_name do |record, attr, value|
          record.errors.add(attr, "must be a Time") if value && (! value.kind_of?(Time))
        end
      end

      # Apply the correct validations for a field of type :timestamp. (Called from #apply_additional_arguments via
      # metaprogramming.)
      def apply_validations_for_timestamp
        apply_validations_for_datetime
      end

      # Apply the correct validations for a field of type :datetime. (Called from #apply_additional_arguments via
      # metaprogramming.)
      def apply_validations_for_datetime
        flex_column_class.validates_each field_name do |record, attr, value|
          record.errors.add(attr, "must be a Time or DateTime") if value && (! value.kind_of?(Time)) && (value.class.name != 'DateTime')
        end
      end

      # Apply the correct validations for a field of type :boolean. (Called from #apply_additional_arguments via
      # metaprogramming.)
      def apply_validations_for_boolean
        flex_column_class.validates field_name, :inclusion => { :in => [ true, false, nil ] }
      end

      # Applies any validations resulting from options to this class (but not types; they're handled by
      # #apply_additional_arguments, above). Currently, this applies validations for +:null+, +:enum+, and +:limit+.
      def apply_validations!
        if options.has_key?(:null) && (! options[:null])
          flex_column_class.validates field_name, :presence => true
        end

        if options.has_key?(:enum)
          values = options[:enum]
          unless values.kind_of?(Array)
            raise ArgumentError, "Must specify an Array of possible values, not: #{options[:enum].inspect}"
          end

          flex_column_class.validates field_name, :inclusion => { :in => values }
        end

        if options.has_key?(:limit)
          limit = options[:limit]
          raise ArgumentError, "Limit must be > 0, not: #{limit.inspect}" unless limit.kind_of?(Integer) && limit > 0

          flex_column_class.validates field_name, :length => { :maximum => limit }
        end
      end
    end
  end
end
