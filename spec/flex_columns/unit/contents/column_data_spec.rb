require 'flex_columns'
require 'flex_columns/helpers/exception_helpers'

describe FlexColumns::Contents::ColumnData do
  include FlexColumns::Helpers::ExceptionHelpers

  before :each do
    @field_set = double("field_set")
    allow(@field_set).to receive(:kind_of?).with(FlexColumns::Definition::FieldSet).and_return(true)
    allow(@field_set).to receive(:all_field_names).with().and_return([ :foo, :bar, :baz ])

    @field_foo = double("field_foo")
    allow(@field_foo).to receive(:field_name).and_return(:foo)
    @field_bar = double("field_bar")
    allow(@field_bar).to receive(:field_name).and_return(:bar)
    @field_baz = double("field_baz")
    allow(@field_baz).to receive(:field_name).and_return(:baz)

    allow(@field_set).to receive(:field_named) do |x|
      case x.to_sym
      when :foo then @field_foo
      when :bar then @field_bar
      when :baz then @field_baz
      else nil
      end
    end

    allow(@field_set).to receive(:field_with_json_storage_name) do |x|
      case x.to_sym
      when :foo then @field_foo
      when :bar then @field_bar
      when :baz then @field_baz
      else nil
      end
    end

    @data_source = double("data_source")
    allow(@data_source).to receive(:describe_flex_column_data_source).with().and_return("describedescribe")
    allow(@data_source).to receive(:notification_hash_for_flex_column_data_source).and_return(:notif1 => :a, :notif2 => :b)

    @json_string = '  {"bar":123,"foo":"bar","baz":"quux"}   '
  end

  def klass
    FlexColumns::Contents::ColumnData
  end

  def new_with_string(s)
    klass.new(@field_set, :data_source => @data_source, :unknown_fields => :preserve, :storage => :text, :json_string => s)
  end

  it "should validate options properly" do
    valid_options = {
      :data_source => @data_source,
      :unknown_fields => :preserve,
      :storage => :text
    }

    lambda { klass.new(double("not_a_field_set"), valid_options) }.should raise_error(ArgumentError)
    lambda { klass.new(@field_set, valid_options.merge(:data_source => nil)) }.should raise_error(ArgumentError)
    lambda { klass.new(@field_set, valid_options.merge(:unknown_fields => :foo)) }.should raise_error(ArgumentError)
    lambda { klass.new(@field_set, valid_options.merge(:storage => :foo)) }.should raise_error(ArgumentError)
    lambda { klass.new(@field_set, valid_options.merge(:length_limit => 'foo')) }.should raise_error(ArgumentError)
    lambda { klass.new(@field_set, valid_options.merge(:length_limit => 3)) }.should raise_error(ArgumentError)
    lambda { klass.new(@field_set, valid_options.merge(:compress_if_over_length => 3.5)) }.should raise_error(ArgumentError)
    lambda { klass.new(@field_set, valid_options.merge(:compress_if_over_length => 'foo')) }.should raise_error(ArgumentError)
  end

  context "with a valid instance" do
    before :each do
      @instance = new_with_string(@json_string)
    end

    describe "[]" do
      it "should reject invalid field names" do
        expect(@field_set).to receive(:field_named).with(:quux).and_return(nil)

        e = capture_exception(FlexColumns::Errors::NoSuchFieldError) { @instance[:quux] }
        e.data_source.should be(@data_source)
        e.field_name.should == :quux
        e.all_field_names.should == [ :foo, :bar, :baz ]
      end

      it "should return data from a valid field correctly" do
        field = double("field")
        allow(field).to receive(:field_name).and_return(:foo)
        expect(@field_set).to receive(:field_named).with(:foo).and_return(field)

        @instance[:foo].should == 'bar'
      end
    end

    describe "deserialization" do
      it "should raise an error if encoding is wrong" do
        bad_encoding = double("bad_encoding")
        allow(bad_encoding).to receive(:kind_of?).with(String).and_return(true)
        expect(bad_encoding).to receive(:valid_encoding?).with().and_return(false)

        exception = StandardError.new("bonk")
        expect(FlexColumns::Errors::IncorrectlyEncodedStringInDatabaseError).to receive(:new).once.with(@data_source, bad_encoding).and_return(exception)

        capture_exception { new_with_string(bad_encoding)[:foo] }.should be(exception)
      end

      it "should accept blank strings just fine" do
        instance = new_with_string("   ")
        instance[:foo].should be_nil
        instance[:bar].should be_nil
        instance[:baz].should be_nil
      end

      it "should raise an error if the JSON doesn't parse" do
        bogus_json = "---unparseable JSON---"
        instance = new_with_string(bogus_json)

        e = capture_exception(FlexColumns::Errors::UnparseableJsonInDatabaseError) { instance[:foo] }
        e.data_source.should be(@data_source)
        e.raw_string.should == bogus_json
        e.source_exception.kind_of?(JSON::ParserError).should be
      end

      it "should raise an error if the JSON doesn't represent a Hash" do
        bogus_json = "[ 1, 2, 3 ]"
        instance = new_with_string(bogus_json)

        e = capture_exception(FlexColumns::Errors::InvalidJsonInDatabaseError) { instance[:foo] }
        e.data_source.should be(@data_source)
        e.raw_string.should == bogus_json
        e.returned_data.should == [ 1, 2, 3 ]
      end

      it "should accept uncompressed strings with a header" do

      end
    end

    describe "unknown-field handling" do
      it "should hang on to unknown data if asked"
      it "should discard unknown data if asked"
      it "should not allow unknown data to conflict with known data"
    end
  end
end
