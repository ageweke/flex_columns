require 'active_support/concern'

module FlexColumns
  module Including
    # IncludeFlexColumns defines the methods on ActiveRecord::Base that get triggered when you say
    # 'include_flex_columns_from' on an ActiveRecord model. Note, however, that it is not simply directly included
    # into ActiveRecord::Base; rather, it's included only when you actually make that declaration, and included
    # into the specific model class itself. (This helps avoid pollution or conflict on any ActiveRecord models that
    # have not used this functionality.)
    #
    # This module works in a pretty different way from FlexColumns::HasFlexColumns, which is the corresponding module
    # that gets included when you declare a flex column with <tt>flex_column :foo do ... end</tt>. That module builds
    # up an object representation of the flex column itself and of all its fields, and then holds onto these objects
    # and uses them to do its work. This module, on the other hand, actively and aggressively defines the appropriate
    # methods when you call #include_flex_columns_from, but does not create or hold onto any object representation of
    # the included columns. This is for two reasons: first off, there's a lot more complexity in defining a flex
    # column itself than in simply including one. Secondly, and more subtly, defining a flex column is a process with
    # a decided start and end -- the contents of the block passed to +flex_column+. Including fields, however, is a
    # component part of a class that's defined using the Ruby +class+ keyword, and which can get reopened and redefined
    # at any given time. Thus, we really have no choice but to aggressively define methods when
    # +include_flex_columns_from+ is called; holding onto an object representation would largely just ensure that that
    # object representation grew incorrect over time in development mode, as columns get defined and redefined over
    # time.
    #
    # (A corollary of this is that, in Rails development mode, depending on how classes get reloaded, it's possible that
    # if you remove an +include_flex_columns_from+ declaration from a model, the defined methods won't actually
    # disappear until you restart your server. There's really not much we can do about this, since there's no Ruby hook
    # that says "someone is defining methods on class X" -- nor would one make any sense, since you can re-open classes
    # at any time and as many times as you want in Ruby.)
    #
    # In comments below, we're working with the following example:
    #
    #    class UserDetail < ActiveRecord::Base
    #      self.primary_key = :user_id
    #      belongs_to :user
    #
    #      flex_column :details do
    #        field :background_color
    #        field :likes_peaches
    #      end
    #    end
    #
    #    class User < ActiveRecord::Base
    #      has_one :detail
    #
    #      include_flex_columns_from :detail
    #    end
    module IncludeFlexColumns
      # Make sure our ClassMethods module gets +extend+ed into any class that +include+s us.
      extend ActiveSupport::Concern

      # This is the method that gets called by generated delegated methods, and called in order to retrieve the
      # correct flex-column object for a column. In other words, the generated method User#background_color looks
      # something like:
      #
      #     def background_color
      #       flex_column_object = _flex_column_object_for(:details)
      #       flex_column_object.background_color
      #     end
      #
      # (We do this partially so that the exact same method definition works for UserDetail and for User; _i.e._,
      # whether you're running on a class that itself has a flex column, or on a class that simply is including another
      # class's flex columns, #_flex_column_object_for will get you the right object.)
      #
      # There's only one nasty case to deal with here: what if User has its own flex column +detail+? In such a case, we
      # want to return the flex-column object that's defined for the column the class has itself, not for the one it's
      # including.
      def _flex_column_object_for(column_name)
        # This is the "nasty case", above.
        begin
          return super(column_name)
        rescue NoMethodError
          # ok
        rescue FlexColumns::Errors::NoSuchColumnError
          # ok
        end

        # Fetch the association that this column is included from.
        association = self.class._flex_column_is_included_from(column_name)

        if association
          # Get the associated object. We automatically will build the associated object, if necessary; this is so that
          # you don't have to either actively create associated objects ahead of time, just in case you need them later,
          # or litter your code with checks to see if those objects exist already or not.
          associated_object = send(association) || send("build_#{association}")
          return associated_object.send(column_name)
        else
          raise FlexColumns::Errors::NoSuchColumnError.new(%{Class #{self.class.name} knows nothing of a flex column named #{column_name.inspect}.})
        end
      end

      module ClassMethods
        # The DynamicMethodsModule on which we define all methods generated by included flex columns.
        def _flex_columns_include_flex_columns_dynamic_methods_module
          @_flex_columns_include_flex_columns_dynamic_methods_module ||= FlexColumns::Util::DynamicMethodsModule.new(self, :FlexColumnsIncludedColumnsMethods)
        end

        # Returns the name of the association from which a flex column of the given name was included.
        def _flex_column_is_included_from(flex_column_name)
          @_included_flex_columns_map[flex_column_name]
        end

        # Includes methods from the given flex column or flex columns into this class.
        #
        # +args+ should be a list of association names from which you want to include columns. It can also end in an
        # options Hash, which can contain:
        #
        # [:prefix] If set, included method names will be prefixed with the given string (followed by an underscore).
        #           If not set, the prefix defined on each flex column, if any, will be used; you can override this by
        #           explicitly passing +nil+ here.
        # [:visibility] If set to +:private+, included methods will be marked +private+, meaning they can only be
        #               accessed from inside this model. This can be used to ensure random code across your system
        #               can't directly manipulate flex-column fields.
        # [:delegate] If set to +false+ or +nil+, then only the method that accesses the flex column itself (above,
        #             User#details) will be created; other methods (User#background_color, User#likes_peaches) will
        #             not be automatically delegated.
        def include_flex_columns_from(*args, &block)
          # Grab our options, and validate them as necessary...
          options = args.pop if args[-1] && args[-1].kind_of?(Hash)
          options ||= { }

          options.assert_valid_keys(:prefix, :visibility, :delegate)

          case options[:prefix]
          when nil, String, Symbol then nil
          else raise ArgumentError, "Invalid value for :prefix: #{options[:prefix].inspect}"
          end

          unless [ :public, :private, nil ].include?(options[:visibility])
            raise ArgumentError, "Invalid value for :visibility: #{options[:visibility].inspect}"
          end

          unless [ true, false, nil ].include?(options[:delegate])
            raise ArgumentError, "Invalid value for :delegate: #{options[:delegate].inspect}"
          end

          association_names = args

          @_included_flex_columns_map ||= { }

          # Iterate through each association...
          association_names.each do |association_name|
            # Get the association and make sure it's of the right type...
            association = reflect_on_association(association_name.to_sym)
            unless association
              raise ArgumentError, %{You asked #{self.name} to include flex columns from association #{association_name.inspect},
  but this class doesn't seem to have such an association. Associations it has are:

    #{reflect_on_all_associations.map(&:name).sort_by(&:to_s).join(", ")}}
            end

            unless [ :has_one, :belongs_to ].include?(association.macro)
              raise ArgumentError, %{You asked #{self.name} to include flex columns from association #{association_name.inspect},
  but that association is of type #{association.macro.inspect}, not :has_one or :belongs_to.

  We can only include flex columns from an association of these types, because otherwise
  there is no way to know which target object to include the data from.}
            end

            # Grab the target model class, and make sure it has one or more flex columns...
            target_class = association.klass
            if (! target_class.respond_to?(:has_any_flex_columns?)) || (! target_class.has_any_flex_columns?)
              raise ArgumentError, %{You asked #{self.name} to include flex columns from association #{association_name.inspect},
  but the target class of that association, #{association.klass.name}, has no flex columns defined.}
            end

            # Call through and tell those flex columns to create the appropriate methods.
            target_class._all_flex_column_names.each do |flex_column_name|
              @_included_flex_columns_map[flex_column_name] = association_name

              flex_column_class = target_class._flex_column_class_for(flex_column_name)
              flex_column_class.include_fields_into(_flex_columns_include_flex_columns_dynamic_methods_module, association_name, self, options)
            end
          end
        end
      end
    end
  end
end
