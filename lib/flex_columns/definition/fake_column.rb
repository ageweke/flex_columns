module FlexColumns
  module Definition
    # This is a class that complies with just enough of the ActiveRecord interface to columns to be able to be
    # swapped in for it, in our code.
    #
    # We use this in just one case: when you declare a flex column on a model class whose underlying table doesn't
    # exist. If you call +.reset_column_information+ on the model in question, we'll pick up the new, actual column
    # (assuming the table exists now), but, until then, we'll use this.
    class FakeColumn
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def null
        true
      end

      def type
        :string
      end
    end
  end
end
