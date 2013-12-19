require 'flex_columns'

describe FlexColumns::Errors do
  def should_be_a_subclass(klass, expected_superclass)
    current = klass

    while current != expected_superclass && current != Object
      current = current.superclass
    end

    if current == Object
      raise "Expected #{klass} to have #{expected_superclass} as a superclass, but it doesn't"
    end
  end

  before :each do
    @data_source = double("data_source")
    allow(@data_source).to receive(:describe_flex_column_data_source).with().and_return("dfcds")
  end

  describe FlexColumns::Errors::FieldError do
    it "should inherit from Base" do
      should_be_a_subclass(FlexColumns::Errors::FieldError, FlexColumns::Errors::Base)
    end
  end

  describe FlexColumns::Errors::NoSuchFieldError do
    it "should inherit from FieldError" do
      should_be_a_subclass(FlexColumns::Errors::NoSuchFieldError, FlexColumns::Errors::FieldError)
    end

    it "should take data_source, data_name, and all_field_names, and use them in its message" do
      instance = FlexColumns::Errors::NoSuchFieldError.new(@data_source, :foo, [ :bar, :baz, :quux ])
      instance.message.should match(/dfcds/i)
      instance.message.should match(/foo/i)
      instance.message.should match(/bar.*baz.*quux/i)

      instance.data_source.should be(@data_source)
      instance.field_name.should == :foo
      instance.all_field_names.should == [ :bar, :baz, :quux ]
    end
  end

  describe FlexColumns::Errors::ConflictingJsonStorageNameError do
    it "should inherit from FieldError" do
      should_be_a_subclass(FlexColumns::Errors::ConflictingJsonStorageNameError, FlexColumns::Errors::FieldError)
    end

    it "should take model_class, column_name, new_field_name, existing_field_name, and json_storage_name" do
      model_class = double("model_class")
      allow(model_class).to receive(:name).with().and_return("mcname")

      instance = FlexColumns::Errors::ConflictingJsonStorageNameError.new(model_class, :foo, :bar, :baz, :quux)
      instance.model_class.should be(model_class)
      instance.column_name.should == :foo
      instance.new_field_name.should == :bar
      instance.existing_field_name.should == :baz
      instance.json_storage_name.should == :quux

      instance.message.should match(/mcname/i)
      instance.message.should match(/foo/i)
      instance.message.should match(/bar/i)
      instance.message.should match(/baz/i)
      instance.message.should match(/quux/i)
    end
  end

  describe FlexColumns::Errors::DefinitionError do
    it "should inherit from Base" do
      should_be_a_subclass(FlexColumns::Errors::DefinitionError, FlexColumns::Errors::Base)
    end
  end

  describe FlexColumns::Errors::NoSuchColumnError do
    it "should inherit from DefinitionError" do
      should_be_a_subclass(FlexColumns::Errors::NoSuchColumnError, FlexColumns::Errors::DefinitionError)
    end
  end

  describe FlexColumns::Errors::InvalidColumnTypeError do
    it "should inherit from DefinitionError" do
      should_be_a_subclass(FlexColumns::Errors::InvalidColumnTypeError, FlexColumns::Errors::DefinitionError)
    end
  end

  describe FlexColumns::Errors::DataError do
    it "should inherit from Base" do
      should_be_a_subclass(FlexColumns::Errors::DataError, FlexColumns::Errors::Base)
    end
  end

  describe FlexColumns::Errors::JsonTooLongError do
    it "should inherit from DataError" do
      should_be_a_subclass(FlexColumns::Errors::JsonTooLongError, FlexColumns::Errors::DataError)
    end

    it "should take data_source, limit, and json_string" do
      instance = FlexColumns::Errors::JsonTooLongError.new(@data_source, 123, "a" * 10_000)
      instance.data_source.should be(@data_source)
      instance.limit.should == 123
      instance.json_string.should == "a" * 10_000

      instance.message.length.should < 1_000
      instance.message.should match(/123/)
      instance.message.should match(/dfcds/)
      instance.message.should match("a" * 30)
    end
  end

  describe FlexColumns::Errors::InvalidDataInDatabaseError do
    it "should inherit from DataError" do
      should_be_a_subclass(FlexColumns::Errors::InvalidDataInDatabaseError, FlexColumns::Errors::DataError)
    end

    it "should take data_source, raw_string, and additional_message" do
      instance = FlexColumns::Errors::InvalidDataInDatabaseError.new(@data_source, "aaa" * 1_000, "holy hell")
      instance.data_source.should be(@data_source)
      instance.raw_string.should == "aaa" * 1_000
      instance.additional_message.should == "holy hell"

      instance.message.length.should < 1_000
      instance.message.should match(/dfcds/)
      instance.message.should match("a" * 20)
      instance.message.should match(/holy hell/)
    end
  end

  describe FlexColumns::Errors::InvalidCompressedDataInDatabaseError do
    it "should inherit from InvalidDataInDatabaseError" do
      should_be_a_subclass(FlexColumns::Errors::InvalidCompressedDataInDatabaseError, FlexColumns::Errors::InvalidDataInDatabaseError)
    end

    it "should take data_source, raw_string, and source_exception" do
      source_exception = double("source_exception")
      source_exception_class = double("source_exception_class")
      allow(source_exception_class).to receive(:name).with().and_return("secname")
      allow(source_exception).to receive(:class).with().and_return(source_exception_class)
      allow(source_exception).to receive(:to_s).with().and_return("seto_s")

      instance = FlexColumns::Errors::InvalidCompressedDataInDatabaseError.new(@data_source, "a" * 1_000, source_exception)
      instance.data_source.should be(@data_source)
      instance.raw_string.should == "a" * 1_000
      instance.source_exception.should be(source_exception)

      instance.message.length.should < 1_000
      instance.message.should match(/dfcds/)
      instance.message.should match("a" * 20)
      instance.message.should match(/secname/)
      instance.message.should match(/seto_s/)
    end
  end
end
