module FlexColumns
  module Definition
    # When you declare a flex column, we actually generate a brand-new Class for that column; instances of that flex
    # column are instances of this new Class. This class acquires functionality from two places: FlexColumnContentsBase,
    # which defines its instance methods, and FlexColumnContentsClass, which defines its class methods. (While
    # FlexColumnContentsBase is an actual Class, FlexColumnContentsClass is a Module that FlexColumnContentsBase
    # +extend+s. Both could be combined, but, simply for readability and maintainability, it was better to make them
    # separate.)
    #
    # This Module therefore defines the methods that are available on a flex-column class -- directly from inside
    # the block passed to +flex_column+, for example.
    module FlexColumnContentsClass
      # By default, how long does the generated JSON have to be before we'll try compressing it?
      DEFAULT_MAX_JSON_LENGTH_BEFORE_COMPRESSION = 200

      # Given a string from storage in +storage_string+, and an object that responds to ColumnData's +data_source+
      # protocol for describing where data came from, create the appropriate ColumnData object to represent that data.
      # (+storage_string+ can absolutely be +nil+, in case there is no data yet.)
      #
      # This is used by instances of the generated Class to create the ColumnData object that does most of the work of
      # actually serializing/deserializing JSON and storing data for that instance.
      def _flex_columns_create_column_data(storage_string, data_source)
        ensure_setup!

        create_options = {
          :storage_string => storage_string,
          :data_source    => data_source,
          :unknown_fields => options[:unknown_fields] || :preserve,
          :length_limit   => column.limit,
          :storage        => column.type == :binary ? :binary : :text,
          :binary_header  => true,
          :null           => column.null
        }

        create_options[:binary_header] = false if options.has_key?(:header) && (! options[:header])

        if (! options.has_key?(:compress))
          create_options[:compress_if_over_length] = DEFAULT_MAX_JSON_LENGTH_BEFORE_COMPRESSION
        elsif options[:compress]
          create_options[:compress_if_over_length] = options[:compress]
        end

        FlexColumns::Contents::ColumnData.new(field_set, create_options)
      end

      # This is what gets called when you declare a field inside a flex column.
      def field(name, *args)
        ensure_setup!
        field_set.field(name, *args)
      end

      # Returns the field with the given name, or nil if there is no such field.
      def field_named(name)
        ensure_setup!
        field_set.field_named(name)
      end

      # Returns the field that stores its JSON under the given key (+json_storage_name+), or nil if there is no such
      # field.
      def field_with_json_storage_name(json_storage_name)
        ensure_setup!
        field_set.field_with_json_storage_name(json_storage_name)
      end

      # Is this a flex-column class? Of course it is, by definition. We just use this for argument validation in some
      # places.
      def is_flex_column_class?
        true
      end

      # Tells this flex column that you want to include its methods into the given +dynamic_methods_module+, which is
      # included in the given +target_class+. (We only use +target_class+ to make sure we don't define methods that
      # are already present on the given +target_class+.) +association_name+ is the name of the association that,
      # from the given +target_class+, will return a model instance that contains this flex column.
      #
      # +options+ specifies options for the inclusion; it can specify +:visibility+ to change whether methods are
      # public or private, +:delegate+ to turn off delegation of anything other than the flex column itself, or
      # +:prefix+ to set a prefix for the delegated method names.
      def include_fields_into(dynamic_methods_module, association_name, target_class, options)
        ensure_setup!

        cn = column_name
        mn = column_name.to_s
        mn = "#{options[:prefix]}_#{mn}" if options[:prefix]

        # Make sure we don't overwrite some #method_missing magic that defines a column accessor, or something
        # similar.
        if target_class._flex_columns_safe_to_define_method?(mn)
          dynamic_methods_module.define_method(mn) do
            associated_object = send(association_name) || send("build_#{association_name}")
            associated_object.send(cn)
          end
          dynamic_methods_module.private(mn) if options[:visibility] == :private
        end

        unless options.has_key?(:delegate) && (! options[:delegate])
          add_custom_methods!(dynamic_methods_module, target_class, options)
          field_set.include_fields_into(dynamic_methods_module, association_name, target_class, options)
        end
      end

      # Given an instance of the model that this flex column is defined on, return the appropriate flex-column
      # object for that instance. This simply delegates to #_flex_column_object_for on that model instance.
      def object_for(model_instance)
        ensure_setup!
        model_instance._flex_column_object_for(column.name)
      end

      # When we delegate methods, what should we prefix them with (if anything)?
      def delegation_prefix
        ensure_setup!
        options[:prefix].try(:to_s)
      end

      # When we delegate methods, should we delegate them at all (returns +nil+), publicly (+:public+), or
      # privately (+:private+)?
      def delegation_type
        ensure_setup!
        return :public if (! options.has_key?(:delegate))

        case options[:delegate]
        when nil, false then nil
        when true, :public then :public
        when :private then :private
        # OK to raise an untyped error here -- we should've caught this in #validate_options.
        else raise "Impossible value for :delegate: #{options[:delegate]}"
        end
      end

      # What's the name of the actual model column this flex-column uses? Returns a Symbol.
      def column_name
        ensure_setup!
        column.name.to_sym
      end

      # What are the names of all fields defined on this flex column?
      def all_field_names
        field_set.all_field_names
      end

      # Given a model instance, do we need to save this column? This is true under one of two cases:
      #
      # * Someone has changed ("touched") at least one of the flex-column fields (or called #touch! on it);
      # * The column is non-NULL, and there's no data in it right now. (Saving it will populate it with an empty string.)
      def requires_serialization_on_save?(model)
        maybe_flex_object = model._flex_column_object_for(column_name, false)
        (maybe_flex_object && maybe_flex_object.touched?) || ((! column.null) && (! model[column_name]))
      end

      # Are fields in this flex column private by default?
      def fields_are_private_by_default?
        ensure_setup!
        options[:visibility] == :private
      end

      # This is, for all intents and purposes, the initializer (constructor) for this module. But because it's a module
      # (and has to be), this can't actually be #initialize. (Another way of saying it: objects have initializers;
      # classes do not.)
      #
      # You must call this method exactly once for each class that extends this module, and before you call any other
      # method.
      #
      # +model_class+ must be the ActiveRecord model class for this flex column. +column_name+ must be the name of
      # the column that you're using as a flex column. +options+ can contain any of:
      #
      # [:visibility] If +:private+, then all field accessors (readers and writers) will be private by default, unless
      #               overridden in their field declaration.
      # [:delegate] If specified and +false+ or +nil+, then field accessors and custom methods defined in this class
      #             will not be automatically delegated to from the +model_class+.
      # [:prefix] If specified (as a Symbol or String), then field accessors and custom methods delegated from the
      #           +model_class+ will be prefixed with this string, followed by an underscore.
      # [:unknown_fields] If specified and +:delete+, then, if the JSON string for an instance contains fields that
      #                   aren't declared in this class, they will be removed from the JSON when saving back out to
      #                   the database. This is dangerous, but powerful, if you want to keep your data clean.
      # [:compress] If specified and +false+, this column will never be compressed. If specified as a number, then,
      #             when serializing data, we'll try to compress it if the uncompressed version is at least that many
      #             bytes long; we'll store the compressed version if it's no more than 95% as long as the uncompressed
      #             version. The default is 200. Also note that compression requires a binary storage type for the
      #             underlying column.
      # [:header] If the underlying column is of binary storage type, then, by default, we use a tiny header to indicate
      #           what kind of data is stored there and whether it's compressed or not. If this is set to +false+,
      #           disables this header (and therefore also disables compression).
      def setup!(model_class, column_name, options = { }, &block)
        raise ArgumentError, "You can't call setup! twice!" if @model_class || @column

        # Make really sure we're being declared in the right kind of class.
        unless model_class.kind_of?(Class) && model_class.respond_to?(:has_any_flex_columns?) && model_class.has_any_flex_columns?
          raise ArgumentError, "Invalid model class: #{model_class.inspect}"
        end

        raise ArgumentError, "Invalid column name: #{column_name.inspect}" unless column_name.kind_of?(Symbol)

        column = model_class.columns.detect { |c| c.name.to_s == column_name.to_s }
        unless column
          raise FlexColumns::Errors::NoSuchColumnError, %{You're trying to define a flex column #{column_name.inspect}, but
  the model you're defining it on, #{model_class.name}, seems to have no column
  named that.

  It has columns named: #{model_class.columns.map(&:name).sort_by(&:to_s).join(", ")}.}
        end

        unless column.type == :binary || column.text? || column.sql_type == "json" # for PostgreSQL >= 9.2, which has a native JSON data type
          raise FlexColumns::Errors::InvalidColumnTypeError, %{You're trying to define a flex column #{column_name.inspect}, but
  that column (on model #{model_class.name}) isn't of a type that accepts text.
  That column is of type: #{column.type.inspect}.}
        end

        validate_options(options)

        @model_class = model_class
        @column = column
        @options = options
        @field_set = FlexColumns::Definition::FieldSet.new(self)

        class_name = "#{column_name.to_s.camelize}FlexContents".to_sym
        @model_class.send(:remove_const, class_name) if @model_class.const_defined?(class_name)
        @model_class.const_set(class_name, self)

        # Keep track of which methods were present before and after calling the block that was passed in; this is how
        # we know which methods were declared custom, so we know which ones to add delegation for.
        methods_before = instance_methods
        block_result = class_eval(&block) if block
        @custom_methods = (instance_methods - methods_before).map(&:to_sym)
        block_result
      end

      # Tells this class to re-publish all its methods to the DynamicMethodsModule it uses internally, and to the
      # model class it's a part of.
      #
      # Because Rails in development mode is constantly redefining classes, and we don't want old cruft that you've
      # removed to hang around, we use a "remove absolutely all methods, then add back only what's defined now"
      # strategy.
      def sync_methods!
        @dynamic_methods_module ||= FlexColumns::Util::DynamicMethodsModule.new(self, :FlexFieldsDynamicMethods)
        @dynamic_methods_module.remove_all_methods!

        field_set.add_delegated_methods!(@dynamic_methods_module, model_class._flex_column_dynamic_methods_module, model_class)

        if delegation_type
          add_custom_methods!(model_class._flex_column_dynamic_methods_module, model_class,
            :visibility => (delegation_type == :private ? :private : :public))
        end
      end

      attr_reader :model_class, :column

      private
      attr_reader :fields, :options, :custom_methods, :field_set

      # Takes all custom methods defined on this flex-column class, and adds delegates to them to the given
      # +dynamic_methods_module+. +target_class+ is checked before each one to make sure we don't have a conflict.
      def add_custom_methods!(dynamic_methods_module, target_class, options = { })
        cn = column_name

        custom_methods.each do |custom_method|
          mn = custom_method.to_s
          mn = "#{options[:prefix]}_#{mn}" if options[:prefix]

          if target_class._flex_columns_safe_to_define_method?(mn)
            dynamic_methods_module.define_method(mn) do |*args, &block|
              flex_object = _flex_column_object_for(cn)
              flex_object.send(custom_method, *args, &block)
            end

            dynamic_methods_module.private(custom_method) if options[:visibility] == :private
          end
        end
      end

      # Check all of our options to make sure they're correct. This is pretty defensive programming, but it is SO
      # much nicer to get an error on startup if you've specified anything incorrectly than way on down the line,
      # possibly in production, when it really matters.
      def validate_options(options)
        unless options.kind_of?(Hash)
          raise ArgumentError, "You must pass a Hash, not: #{options.inspect}"
        end

        options.assert_valid_keys(:visibility, :prefix, :delegate, :unknown_fields, :compress, :header)

        unless [ nil, :private, :public ].include?(options[:visibility])
          raise ArgumentError, "Invalid value for :visibility: #{options[:visibility.inspect]}"
        end

        unless [ :delete, :preserve, nil ].include?(options[:unknown_fields])
          raise ArgumentError, "Invalid value for :unknown_fields: #{options[:unknown_fields].inspect}"
        end

        unless [ true, false, nil ].include?(options[:compress]) || options[:compress].kind_of?(Integer)
          raise ArgumentError, "Invalid value for :compress: #{options[:compress].inspect}"
        end

        unless [ true, false, nil ].include?(options[:header])
          raise ArgumentError, "Invalid value for :header: #{options[:header].inspect}"
        end

        case options[:prefix]
        when nil then nil
        when String, Symbol then nil
        else raise ArgumentError, "Invalid value for :prefix: #{options[:prefix].inspect}"
        end

        unless [ nil, true, false, :private, :public ].include?(options[:delegate])
          raise ArgumentError, "Invalid value for :delegate: #{options[:delegate].inspect}"
        end

        if options[:visibility] == :private && options[:delegate] == :public
          raise ArgumentError, "You can't have public delegation if methods in the flex column are private; this makes no sense, as methods in the model class would have *greater* visibility than methods on the flex column itself"
        end
      end

      # Make sure someone has called setup! previously.
      def ensure_setup!
        unless @model_class
          raise "You must call #setup! on this class before calling this method."
        end
      end
    end
  end
end
