module FlexColumns
  module Options
    # === Column-method control:
    #
    #     field :foo, :column_method => false
    #
    # Creates a field that has no reader or writer methods for it. (You can also pass +nil+.) The only way of accessing
    # its value is by hash-indexing the flex-column object (e.g., <tt>preferences[:foo]</tt>,
    # <tt>preferences[:foo] = :bar</tt>).
    #
    #     field :foo, :column_method => :private
    #
    # Creates a field that has reader and writer methods as normal, but which are marked +private+, and thus are only
    # accessible from inside the flex-column object.
    #
    #     field :foo, :column_method => { :name => 'foobar' }
    #
    # Creates a field that has reader and writer methods, but those methods are named +foobar+ and +foobar=+, not
    # +foo+ and +foo=+.
    #
    #     field :foo, :column_method => { :name => 'foobar', :visibility => :private }
    #
    # Use this to combine both +:name+ and visibility.
    #
    # === Instance-method control:
    #
    #     field :foo, :instance_method => false
    #
    # Creates a field that will have no method created in the containing instance for it. (You can also pass +nil+.)
    #
    #     field :foo, :instance_method => :private
    #
    # Creates a field that will have an method created in the containing instance, but which will be marked as
    # +private+ and thus only will be accessible from inside that object.
    #
    #     field :foo, :instance_method => { :name => 'barbaz' }
    #
    # Creates a field that will have normal reader and writer methods created for it in the containing instance, but
    # which will be called +barbaz+ and +barbaz=+ (rather than +foo+ and +foo=+).
    #
    #     field :foo, :instance_method => { :writer => false }
    #
    # Creates a field that will have a normal reader method for it defined on the containing instance, but no writer
    # method.
    #
    #     field :foo, :instance_method => { :name => 'barbaz', :visibility => :private, :writer => false }
    #
    # Use this to combine +:name+, visibility, and +:writer+.
    #
    # === Accessibility control:
    #
    #     field :foo, :accessible => false
    #
    # Defines a field +foo+ that cannot be accessed &mdash; not via methods, and not via hash-indexing. Why would you
    # want to do this? Because if you have <tt>:unknown_fields => :delete</tt> on the flex column, then, without this,
    # any value in that field will be deleted. This lets you preserve any value in that field, without allowing access
    # from your code; this is useful if there's data there that some other application uses, but which yours absolutely
    # shouldn't touch.
    #
    # === Read-only control:
    #
    #     field :foo, :read_only => true
    #
    # Defines a field +foo+ that can be read from, but not written &mdash; not via methods, and not via hash-indexing.
    # This is useful if there's data you need to be able to read, but which you absolutely shouldn't be writing.
    class FieldOptions
      def initialize(field_definition, options_hash, column_options)
        @field_definition = field_definition

        raise ArgumentError, "Options must be a Hash, not: #{options_hash.inspect}" unless options_hash.kind_of?(Hash)
        options_hash.assert_valid_keys(:column_method, :read_only, :accessible)

        @column_options = column_options

        set_column_method_from_hash!(options_hash)
        set_instance_method_from_hash!(options_hash)
        set_read_only_from_hash!(options_hash)
        set_accessible_from_hash!(options_hash)
      end

      def generate_column_reader_method?
        !! (@has_column_method && readable?)
      end

      def generate_column_writer_method?
        !! (@has_column_method && readable? && writable?)
      end

      def writable?
        readable? && (! @read_only)
      end

      def column_method_name
        @column_method_name || field_definition.field_name
      end

      def column_method_visibility
        @column_method_visibility
      end

      def readable?
        !! @accessible
      end

      private
      attr_reader :field_definition

      def set_column_method_from_hash!(options_hash)
        @has_column_method = true
        @column_method_visibility = :public
        @column_method_name = nil

        if [ :public, :private ].include?(options_hash[:column_method])
          @column_method_visibility = method_data
        elsif options_hash.has_key?(:column_method) && (! options_hash[:column_method])
          @has_column_method = false
        elsif options_hash[:column_method] == true
          # no-op, already have @has_column_method = true, above
        elsif options_hash[:column_method].kind_of?(Hash)
          column_method_hash = options_hash[:column_method]
          column_method_hash.assert_valid_keys(:visibility, :name)

          if column_method_hash.has_key?(:visibility)
            if [ :public, :private ].include?(column_method_hash[:visibility])
              @column_method_visibility = column_method_hash[:visibility]
            else
              raise ArgumentError, "Invalid value for :visibility: #{column_method_hash[:visibility].inspect}"
            end
          end

          if column_method_hash.has_key?(:name)
            if column_method_hash[:name].kind_of?(String) || column_method_hash[:name].kind_of?(Symbol)
              @column_method_name = column_method_hash[:name].to_s
            else
              raise ArgumentError, "Invalid value for :name: #{column_method_hash[:name].inspect}"
            end
          end
        elsif options_hash[:column_method]
          raise ArgumentError, "Invalid specification for :column_method in options: #{options_hash[:column_method].inspect}"
        end
      end

      def set_instance_method_from_hash!(options_hash)
        @has_instance_method = true
        @instance_method_visibility = :public
        @instance_method_name = nil
        @instance_writer_method = true

        # FILL IN HERE
      end

      def set_read_only_from_hash!(options_hash)
        if options_hash.has_key?(:read_only)
          if [ true, false, nil ].include?(options_hash[:read_only])
            @read_only = options_hash[:read_only]
          else
            raise ArgumentError, "Invalid value for :read_only: #{options_hash[:read_only].inspect}"
          end
        end
      end

      def set_accessible_from_hash!(options_hash)
        @accessible = true

        if options_hash.has_key?(:accessible)
          if [ true, false, nil ].include?(options_hash[:accessible])
            @accessible = options_hash[:accessible]
          else
            raise ArgumentError, "Invalid value for :accessible: #{options_hash[:accessible].inspect}"
          end
        end
      end
    end
  end
end
