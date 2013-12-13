require 'flex_columns'
require 'flex_columns/contents/flex_column_contents_class'
require 'flex_columns/helpers/exception_helpers'

describe FlexColumns::Contents::FlexColumnContentsClass do
  include FlexColumns::Helpers::ExceptionHelpers

  before :each do
    @klass = Class.new
    @klass.send(:extend, FlexColumns::Contents::FlexColumnContentsClass)

    @model_class = double("model_class")
    allow(@model_class).to receive(:kind_of?).with(Class).and_return(true)
    allow(@model_class).to receive(:has_any_flex_columns?).with().and_return(true)
    allow(@model_class).to receive(:name).with().and_return(:mcname)

    @column_foo = double("column_foo")
    allow(@column_foo).to receive(:name).with().and_return(:foo)
    allow(@column_foo).to receive(:type).with().and_return(:text)
    allow(@column_foo).to receive(:text?).with().and_return(true)
    allow(@column_foo).to receive(:sql_type).with().and_return('clob')

    @column_bar = double("column_bar")
    allow(@column_bar).to receive(:name).with().and_return(:bar)
    allow(@column_bar).to receive(:type).with().and_return(:binary)
    allow(@column_bar).to receive(:text?).with().and_return(false)
    allow(@column_bar).to receive(:sql_type).with().and_return('blob')

    @column_baz = double("column_baz")
    allow(@column_baz).to receive(:name).with().and_return(:baz)
    allow(@column_baz).to receive(:type).with().and_return(:integer)
    allow(@column_baz).to receive(:text?).with().and_return(false)
    allow(@column_baz).to receive(:sql_type).with().and_return('integer')

    @column_ajson = double("column_ajson")
    allow(@column_ajson).to receive(:name).with().and_return(:ajson)
    allow(@column_ajson).to receive(:type).with().and_return(nil)
    allow(@column_ajson).to receive(:text?).with().and_return(false)
    allow(@column_ajson).to receive(:sql_type).with().and_return('json')

    columns = [ @column_foo, @column_bar, @column_baz, @column_ajson ]
    allow(@model_class).to receive(:columns).with().and_return(columns)

    allow(@model_class).to receive(:const_defined?).and_return(false)
    allow(@model_class).to receive(:const_set)

    @field_set = double("field_set")
    allow(FlexColumns::Definition::FieldSet).to receive(:new).and_return(@field_set)
  end

  describe "setup!" do
    describe "pre-setup errors" do
      def should_raise_if_not_set_up(&block)
        block.should raise_error(/setup!/i)
      end

      it "should raise an error if any other method is called" do
        should_raise_if_not_set_up { @klass._flex_columns_create_column_data(double("storage_string"), double("data_source")) }
        should_raise_if_not_set_up { @klass.field(:foo) }
        should_raise_if_not_set_up { @klass.field_named(:foo) }
        should_raise_if_not_set_up { @klass.field_with_json_storage_name(:foo) }
        should_raise_if_not_set_up { @klass.include_fields_into(double("dynamic_methods_module"),
          double("association_name"), double("target_class"), { }) }
        should_raise_if_not_set_up { @klass.object_for(double("model_instance")) }
        should_raise_if_not_set_up { @klass.delegation_prefix }
        should_raise_if_not_set_up { @klass.delegation_type }
        should_raise_if_not_set_up { @klass.column_name }
        should_raise_if_not_set_up { @klass.fields_are_private_by_default? }
      end
    end

    it "should work with no options" do
      @klass.setup!(@model_class, :foo) { }
    end

    it "should not allow itself to be called twice" do
      @klass.setup!(@model_class, :foo) { }

      lambda { @klass.setup!(@model_class, :foo) { } }.should raise_error(ArgumentError)
    end

    it "should require a model class that's a class" do
      mc = double("model_class")
      expect(mc).to receive(:kind_of?).with(Class).and_return(false)
      lambda { @klass.setup!(mc, :foo) { } }.should raise_error(ArgumentError)
    end

    it "should require a model class that's an AR class" do
      allow(@model_class).to receive(:has_any_flex_columns?).with().and_return(false)
      lambda { @klass.setup!(@model_class, :foo) { } }.should raise_error(ArgumentError)
    end

    it "should require a column name that's a Symbol" do
      lambda { @klass.setup!(@model_class, 'foo') { } }.should raise_error(ArgumentError)
    end

    it "should raise a nice error if passed something that isn't a column on the model" do
      e = capture_exception(FlexColumns::Errors::NoSuchColumnError) { @klass.setup!(@model_class, :quux) { } }
      e.message.should match(/quux/i)
      e.message.should match(/foo/i)
      e.message.should match(/bar/i)
      e.message.should match(/baz/i)
      e.message.should match(/mcname/i)
    end

    it "should raise a nice error if passed a column of the wrong type" do
      e = capture_exception(FlexColumns::Errors::InvalidColumnTypeError) { @klass.setup!(@model_class, :baz) { } }
      e.message.should match(/mcname/i)
      e.message.should match(/baz/i)
      e.message.should match(/integer/i)
    end

    it "should work on a text column" do
      @klass.setup!(@model_class, :foo) { }
    end

    it "should work on a binary column" do
      @klass.setup!(@model_class, :bar) { }
    end

    it "should work on a JSON column" do
      @klass.setup!(@model_class, :ajson) { }
    end

    it "should create a new field set and name itself properly" do
      expect(FlexColumns::Definition::FieldSet).to receive(:new).once.with(@klass).and_return(@field_set)

      expect(@model_class).to receive(:const_defined?).with(:FooFlexContents).and_return(false)
      expect(@model_class).to receive(:const_set).once.with(:FooFlexContents, @klass)

      @klass.setup!(@model_class, :foo) { }
    end

    it "should run the block it's passed" do
      expect(@klass).to receive(:foobar).once.with(:foo, :bar, :baz).and_return(:quux)

      @klass.setup!(@model_class, :foo) do
        foobar(:foo, :bar, :baz)
      end.should == :quux
    end

    describe "options validation" do
      def should_reject(options)
        lambda { @klass.setup!(@model_class, :foo, options) { } }.should raise_error(ArgumentError)
      end

      it "should require a Hash" do
        should_reject(123)
      end

      it "should reject unknown keys" do
        should_reject(:foo => 123)
      end

      it "should require a valid option for :visibility" do
        should_reject(:visibility => :foo)
        should_reject(:visibility => true)
      end

      it "should require a valid option for :unknown_fields" do
        should_reject(:unknown_fields => :foo)
        should_reject(:unknown_fields => false)
      end

      it "should require a valid option for :compress" do
        should_reject(:compress => :foo)
        should_reject(:compress => "foo")
      end

      it "should require a valid option for :header" do
        should_reject(:header => :foo)
        should_reject(:header => "foo")
        should_reject(:header => 123)
      end

      it "should require a valid option for :prefix" do
        should_reject(:prefix => true)
        should_reject(:prefix => 123)
      end

      it "should require a valid option for :delegate" do
        should_reject(:delegate => :foo)
        should_reject(:delegate => 123)
      end

      it "should reject incompatible :visibility and :delegate options" do
        should_reject(:visibility => :private, :delegate => :public)
      end
    end
  end

  describe "_flex_columns_create_column_data" do
    def expect_options_transform(class_options, length_limit, resulting_options, column_name = :foo, storage_string = double("storage_string"))
      @klass.setup!(@model_class, column_name, class_options)

      data_source = double("data_source")

      allow(instance_variable_get("@column_#{column_name}")).to receive(:limit).with().and_return(length_limit)

      resulting_options = { :storage_string => storage_string, :data_source => data_source }.merge(resulting_options)

      expect(FlexColumns::Contents::ColumnData).to receive(:new).once.with(@field_set, resulting_options)

      @klass._flex_columns_create_column_data(storage_string, data_source)
    end

    it "should create a new ColumnData object with correct default options" do
      expect_options_transform({ }, nil, {
        :unknown_fields => :preserve,
        :length_limit => nil,
        :storage => :text,
        :binary_header => true,
        :compress_if_over_length => 200
      })
    end

    it "should allow a nil storage string" do
      expect_options_transform({ }, nil, {
        :unknown_fields => :preserve,
        :length_limit => nil,
        :storage => :text,
        :binary_header => true,
        :compress_if_over_length => 200,
        :storage_string => nil
      }, :foo, nil)
    end

    it "should pass through :unknown_fields correctly" do
      expect_options_transform({ :unknown_fields => :delete }, nil, {
        :unknown_fields => :delete,
        :length_limit => nil,
        :storage => :text,
        :binary_header => true,
        :compress_if_over_length => 200
      })
    end

    it "should pass through the column limit correctly" do
      expect_options_transform({ }, 123, {
        :unknown_fields => :preserve,
        :length_limit => 123,
        :storage => :text,
        :binary_header => true,
        :compress_if_over_length => 200
      })
    end

    it "should pass through the column type correctly for a binary column" do
      expect_options_transform({ }, 123, {
        :unknown_fields => :preserve,
        :length_limit => 123,
        :storage => :binary,
        :binary_header => true,
        :compress_if_over_length => 200
      }, :bar)
    end

    it "should pass through the column type correctly for a JSON column" do
      expect_options_transform({ }, 123, {
        :unknown_fields => :preserve,
        :length_limit => 123,
        :storage => :text,
        :binary_header => true,
        :compress_if_over_length => 200
      }, :ajson)
    end

    it "should pass through disabled compression correctly" do
      expect_options_transform({ :compress => false }, nil, {
        :unknown_fields => :preserve,
        :length_limit => nil,
        :storage => :text,
        :binary_header => true
      })
    end

    it "should pass through a compression setting correctly" do
      expect_options_transform({ :compress => 234 }, nil, {
        :unknown_fields => :preserve,
        :length_limit => nil,
        :storage => :text,
        :binary_header => true,
        :compress_if_over_length => 234
      })
    end

    it "should pass through a no-binary-header setting correctly" do
      expect_options_transform({ :header => false }, nil, {
        :unknown_fields => :preserve,
        :length_limit => nil,
        :storage => :text,
        :binary_header => false,
        :compress_if_over_length => 200
      })
    end
  end

  context "with a set-up class" do
    before :each do
      @klass.setup!(@model_class, :foo) { }
    end

    it "should pass through :field to the field set" do
      expect(@field_set).to receive(:field).once.with(:foo, :bar, :baz => :quux)
      @klass.field(:foo, :bar, :baz => :quux)
    end

    it "should pass through :field_named to the field set" do
      expect(@field_set).to receive(:field_named).once.with(:quux).and_return(:bar)
      @klass.field_named(:quux).should == :bar
    end

    it "should pass through :field_with_json_storage_name to the field set" do
      expect(@field_set).to receive(:field_with_json_storage_name).once.with(:quux).and_return(:bar)
      @klass.field_with_json_storage_name(:quux).should == :bar
    end

    it "should be a flex-column class" do
      @klass.is_flex_column_class?.should be
    end

    describe "#include_fields_into" do
      before :each do
        @dmm = Class.new
        @dmm.class_eval do
          def bar_return=(x)
            @bar_return = x
          end

          def bar
            @bar_return
          end

          def build_bar_return=(x)
            @build_bar_return = x
          end

          def build_bar
            @build_bar_return
          end

          def set_flex_column_object_for!(x, y)
            @_flex_column_objects_for ||= { }
            @_flex_column_objects_for[x] = y
          end

          def _flex_column_object_for(x)
            @_flex_column_objects_for[x]
          end

          class << self
            public :define_method, :private
          end
        end

        @target_class = double("target_class")
        @associated_object = double("associated_object")
      end

      it "should define a method that's safe to define, and nothing else, if :delegate => false" do
        expect(@target_class).to receive(:_flex_columns_safe_to_define_method?).with("foo").and_return(true)

        @klass.include_fields_into(@dmm, :bar, @target_class, { :delegate => false })

        expect(@associated_object).to receive(:foo).once.and_return(:quux)
        instance = @dmm.new
        instance.bar_return = @associated_object

        instance.foo.should == :quux
      end

      it "should define a method that falls back to build_<x>" do
        expect(@target_class).to receive(:_flex_columns_safe_to_define_method?).with("foo").and_return(true)

        @klass.include_fields_into(@dmm, :bar, @target_class, { :delegate => false })

        expect(@associated_object).to receive(:foo).once.and_return(:quux)
        instance = @dmm.new
        instance.build_bar_return = @associated_object
        instance.foo.should == :quux
      end

      it "should define a method that's private, if requested" do
        defined_block = nil

        expect(@target_class).to receive(:_flex_columns_safe_to_define_method?).with("foo").and_return(true)

        @klass.include_fields_into(@dmm, :bar, @target_class, { :delegate => false, :visibility => :private })

        expect(@associated_object).to receive(:foo).once.and_return(:quux)
        instance = @dmm.new
        instance.bar_return = @associated_object

        lambda { instance.foo }.should raise_error(NoMethodError)
        instance.send(:foo).should == :quux
      end

      it "should prefix the method name, if requested" do
        defined_block = nil

        expect(@target_class).to receive(:_flex_columns_safe_to_define_method?).with("baz_foo").and_return(true)

        @klass.include_fields_into(@dmm, :bar, @target_class, { :delegate => false, :prefix => "baz" })

        expect(@associated_object).to receive(:foo).once.and_return(:quux)
        instance = @dmm.new
        instance.bar_return = @associated_object

        instance.baz_foo.should == :quux
      end

      it "should add custom methods, and prefix them if needed" do
        @klass = Class.new
        @klass.send(:extend, FlexColumns::Contents::FlexColumnContentsClass)
        @klass.setup!(@model_class, :foo) { def cm1(*args); "cm1!: #{args.join(", ")}: #{yield *args}"; end }

        defined_block = nil
        cm_defined_block = nil

        expect(@target_class).to receive(:_flex_columns_safe_to_define_method?).with("baz_foo").and_return(true)
        expect(@target_class).to receive(:_flex_columns_safe_to_define_method?).with("baz_cm1").and_return(true)

        expect(@field_set).to receive(:include_fields_into).once.with(@dmm, :bar, @target_class, { :prefix => "baz" })

        @klass.include_fields_into(@dmm, :bar, @target_class, { :prefix => "baz" })

        expect(@associated_object).to receive(:foo).once.and_return(:quux)
        instance = @dmm.new
        instance.bar_return = @associated_object

        instance.baz_foo.should == :quux

        flex_object = Object.new
        class << flex_object
          def cm1(*args, &b)
            "cm1 - #{args.join(", ")} - #{b.call(*args)}"
          end
        end

        instance.set_flex_column_object_for!(:foo, flex_object)
        result = instance.baz_cm1(:bar, :baz) { |*args| args.join("X") }
        result.should == "cm1 - bar, baz - barXbaz"
      end
    end
  end
end
