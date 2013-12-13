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

    @field_set = double("field_set")
    allow(FlexColumns::Definition::FieldSet).to receive(:new).and_return(@field_set)
  end

  describe "setup!" do
    it "should work with no options" do
      expect(@model_class).to receive(:const_defined?).with(:FooFlexContents).and_return(false)
      expect(@model_class).to receive(:const_set).once.with(:FooFlexContents, @klass)
      @klass.setup!(@model_class, :foo) { }
    end

    it "should not allow itself to be called twice" do
      expect(@model_class).to receive(:const_defined?).with(:FooFlexContents).and_return(false)
      expect(@model_class).to receive(:const_set).once.with(:FooFlexContents, @klass)
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
      expect(@model_class).to receive(:const_defined?).with(:FooFlexContents).and_return(false)
      expect(@model_class).to receive(:const_set).once.with(:FooFlexContents, @klass)
      @klass.setup!(@model_class, :foo) { }
    end

    it "should work on a binary column" do
      expect(@model_class).to receive(:const_defined?).with(:BarFlexContents).and_return(false)
      expect(@model_class).to receive(:const_set).once.with(:BarFlexContents, @klass)
      @klass.setup!(@model_class, :bar) { }
    end

    it "should work on a JSON column" do
      expect(@model_class).to receive(:const_defined?).with(:AjsonFlexContents).and_return(false)
      expect(@model_class).to receive(:const_set).once.with(:AjsonFlexContents, @klass)
      @klass.setup!(@model_class, :ajson) { }
    end

    it "should create a new field set and name itself properly" do
      expect(FlexColumns::Definition::FieldSet).to receive(:new).once.with(@klass).and_return(@field_set)

      expect(@model_class).to receive(:const_defined?).with(:FooFlexContents).and_return(false)
      expect(@model_class).to receive(:const_set).once.with(:FooFlexContents, @klass)

      @klass.setup!(@model_class, :foo) { }
    end

    it "should run the block it's passed" do
      expect(@model_class).to receive(:const_defined?).with(:FooFlexContents).and_return(false)
      expect(@model_class).to receive(:const_set).once.with(:FooFlexContents, @klass)

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
end
