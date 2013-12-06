module FlexColumns
  module Options
    # === Column-method control:
    #
    #    flex_column :foo, :column_methods => false do ...
    #
    # Do not generate methods on the flex-column object itself for its fields, by default. Passing a +:method+ option to
    # an individual field definition overrides this.
    #
    #    flex_column :foo, :column_methods => :private do ...
    #
    # Make the default visibility of methods on the flex column itself private. This can also be overridden on a
    # field-by-field basis with options on the field definitions themselves.
    #
    # === Read-only control:
    #
    #    flex_column :foo, :read_only => true do ...
    #
    # Make fields in this column read-only by default. (This applies both to methods and hash-indexing; there will be
    # literally no way to write such fields.) This can be overridden on a field-by-field basis with options on the
    # field definitions themselves.
    #
    # === Delegation control:
    #
    #    flex_column :foo, :instance_methods => false do ...
    #
    # Do not generate methods on the containing ActiveRecord model at all.
    #
    #    flex_column
    class ColumnOptions
      def initialize(column_class, options_hash)
        @column_class = column_class

        raise ArgumentError, "Options must be a Hash, not: #{options_hash.inspect}" unless options_hash.kind_of?(Hash)
        options_hash.assert_valid_keys(:column_methods, :instance_methods, :unknown_fields)

        @column_options = column_options

        set_method_from_hash!(options_hash)
        set_read_only_from_hash!(options_hash)
        set_accessible_from_hash!(options_hash)
      end
    end
  end
end
