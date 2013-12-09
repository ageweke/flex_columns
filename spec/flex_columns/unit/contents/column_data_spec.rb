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
        e.message.should match(/describedescribe/)
      end

      it "should raise an error if the JSON doesn't represent a Hash" do
        bogus_json = "[ 1, 2, 3 ]"
        instance = new_with_string(bogus_json)

        e = capture_exception(FlexColumns::Errors::InvalidJsonInDatabaseError) { instance[:foo] }
        e.data_source.should be(@data_source)
        e.raw_string.should == bogus_json
        e.returned_data.should == [ 1, 2, 3 ]
        e.message.should match(/describedescribe/)
      end

      it "should accept uncompressed strings with a header" do
        instance = new_with_string("FC:01,0,#{@json_string}")
        instance[:foo].should == "bar"
        instance[:bar].should == 123
        instance[:baz].should == "quux"
      end

      it "should accept compressed strings with a header" do
        require 'stringio'
        stream = StringIO.new("w")
        writer = Zlib::GzipWriter.new(stream)
        writer.write(@json_string)
        writer.close

        header = "FC:01,1,"
        header.force_encoding("BINARY") if header.respond_to?(:force_encoding)
        instance = new_with_string(header + stream.string)
        instance[:foo].should == "bar"
        instance[:bar].should == 123
        instance[:baz].should == "quux"
      end

      it "should fail if the version number is too big" do
        bad_string = "FC:02,0,#{@json_string}"
        instance = new_with_string(bad_string)

        e = capture_exception(FlexColumns::Errors::InvalidFlexColumnsVersionNumberInDatabaseError) { instance[:foo] }
        e.data_source.should be(@data_source)
        e.raw_string.should == bad_string.strip
        e.version_number_in_database.should == 2
        e.max_version_number_supported.should == 1
        e.message.should match(/describedescribe/)
      end

      it "should fail if the compression number is too big" do
        require 'stringio'
        stream = StringIO.new("w")
        writer = Zlib::GzipWriter.new(stream)
        writer.write(@json_string)
        writer.close

        header = "FC:01,2,"
        header.force_encoding("BINARY") if header.respond_to?(:force_encoding)
        bad_string = header + stream.string

        instance = new_with_string(bad_string)
        e = capture_exception(FlexColumns::Errors::InvalidDataInDatabaseError) { instance[:foo] }
        e.data_source.should be(@data_source)
        e.raw_string.should == bad_string.strip
        e.message.should match(/2/)
        e.message.should match(/describedescribe/)
      end

      it "should fail if the compressed data is bogus" do
        require 'stringio'
        stream = StringIO.new("w")
        writer = Zlib::GzipWriter.new(stream)
        writer.write(@json_string)
        writer.close
        compressed_data = stream.string

        100.times do
          pos_1 = rand(10)
          pos_2 = rand(10)
          tmp = compressed_data[pos_1]
          compressed_data[pos_1] = compressed_data[pos_2]
          compressed_data[pos_2] = tmp
        end

        header = "FC:01,1,"
        header.force_encoding("BINARY") if header.respond_to?(:force_encoding)
        bad_string = header + compressed_data

        instance = new_with_string(bad_string)
        e = capture_exception(FlexColumns::Errors::InvalidCompressedDataInDatabaseError) { instance[:foo] }
        e.data_source.should be(@data_source)
        e.raw_string.should == bad_string.strip
        e.source_exception.class.should == Zlib::GzipFile::Error
        e.message.should match(/describedescribe/)
      end
    end

    describe "unknown-field handling" do
      it "should hang on to unknown data if asked"
      it "should discard unknown data if asked"
      it "should not allow unknown data to conflict with known data"
    end
  end
end
