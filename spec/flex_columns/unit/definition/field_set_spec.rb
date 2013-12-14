require 'flex_columns'
require 'flex_columns/helpers/exception_helpers'

describe FlexColumns::Definition::FieldSet do
  include FlexColumns::Helpers::ExceptionHelpers

  def klass
    FlexColumns::Definition::FieldSet
  end

  before :each do
    @model_class = double("model_class")
    allow(@model_class).to receive(:name).with().and_return("modname")

    @flex_column_class = double("flex_column_class")
    allow(@flex_column_class).to receive(:model_class).with().and_return(@model_class)
    allow(@flex_column_class).to receive(:column_name).with().and_return("colname")

    @instance = klass.new(@flex_column_class)
  end

  it "should allow defining fields and returning them" do
    @field_foo = double("field_foo")
    allow(@field_foo).to receive(:json_storage_name).with().and_return(:foo_storage)

    @field_bar = double("field_bar")
    allow(@field_bar).to receive(:json_storage_name).with().and_return(:storage_bar)

    expect(FlexColumns::Definition::FieldDefinition).to receive(:new).once.with(@flex_column_class, :foo, [ ], { }).and_return(@field_foo)
    @instance.field(' fOo ')

    expect(FlexColumns::Definition::FieldDefinition).to receive(:new).once.with(@flex_column_class, :bar, [ ], { }).and_return(@field_bar)
    @instance.field(:bar)

    @instance.all_field_names.sort_by(&:to_s).should == [ :foo, :bar ].sort_by(&:to_s)

    @instance.field_named(:foo).should be(@field_foo)
    @instance.field_named(' foO ').should be(@field_foo)

    @instance.field_named(:bar).should be(@field_bar)
    @instance.field_named('BAr        ').should be(@field_bar)

    @instance.field_with_json_storage_name(:foo).should_not be
    @instance.field_with_json_storage_name(' fOo ').should_not be
    @instance.field_with_json_storage_name(:foo_storage).should be(@field_foo)

    @instance.field_with_json_storage_name(:bar_storage).should_not be
    @instance.field_with_json_storage_name(:bar).should_not be
    @instance.field_with_json_storage_name(:storage_bar).should be(@field_bar)
  end

  it "should raise if there's a duplicate JSON storage name" do
    @field_foo = double("field_foo")
    allow(@field_foo).to receive(:json_storage_name).with().and_return(:foo_storage)
    allow(@field_foo).to receive(:field_name).with().and_return(:foo)

    @field_bar = double("field_bar")
    allow(@field_bar).to receive(:json_storage_name).with().and_return(:foo_storage)
    allow(@field_bar).to receive(:field_name).with().and_return(:bar)

    expect(FlexColumns::Definition::FieldDefinition).to receive(:new).once.with(@flex_column_class, :foo, [ ], { }).and_return(@field_foo)
    @instance.field(' fOo ')

    expect(FlexColumns::Definition::FieldDefinition).to receive(:new).once.with(@flex_column_class, :bar, [ ], { }).and_return(@field_bar)

    e = capture_exception(FlexColumns::Errors::ConflictingJsonStorageNameError) do
      @instance.field(:bar)
    end

    e.model_class.should be(@model_class)
    e.column_name.should == "colname"
    e.new_field_name.should == :bar
    e.existing_field_name.should == :foo
    e.json_storage_name.should == :foo_storage
  end

  it "should allow redefining the same field, and the new field should win" do
    @field_foo_1 = double("field_foo_1")
    allow(@field_foo_1).to receive(:json_storage_name).with().and_return(:foo_storage)
    allow(@field_foo_1).to receive(:field_name).with().and_return(:foo)

    @field_foo_2 = double("field_foo_2")
    allow(@field_foo_2).to receive(:json_storage_name).with().and_return(:foo_storage)
    allow(@field_foo_2).to receive(:field_name).with().and_return(:foo)

    expect(FlexColumns::Definition::FieldDefinition).to receive(:new).once.with(@flex_column_class, :foo, [ ], { }).and_return(@field_foo_1)
    @instance.field(' fOo ')

    expect(FlexColumns::Definition::FieldDefinition).to receive(:new).once.with(@flex_column_class, :foo, [ ], { :null => false }).and_return(@field_foo_2)
    @instance.field(:foo, :null => false)

    @instance.all_field_names.should == [ :foo ]
    @instance.field_named(:foo).should be(@field_foo_2)
  end

  it "should call through to the fields on #add_delegated_methods!" do
    @field_foo = double("field_foo")
    allow(@field_foo).to receive(:json_storage_name).with().and_return(:foo)

    @field_bar = double("field_bar")
    allow(@field_bar).to receive(:json_storage_name).with().and_return(:bar)

    expect(FlexColumns::Definition::FieldDefinition).to receive(:new).once.with(@flex_column_class, :foo, [ ], { }).and_return(@field_foo)
    @instance.field(:foo)

    expect(FlexColumns::Definition::FieldDefinition).to receive(:new).once.with(@flex_column_class, :bar, [ ], { }).and_return(@field_bar)
    @instance.field(:bar)

    flex_column_dmm = double("flex_column_dmm")
    model_dmm = double("model_dmm")

    expect(@field_foo).to receive(:add_methods_to_flex_column_class!).once.with(flex_column_dmm)
    expect(@field_foo).to receive(:add_methods_to_model_class!).once.with(model_dmm, @model_class)
    expect(@field_bar).to receive(:add_methods_to_flex_column_class!).once.with(flex_column_dmm)
    expect(@field_bar).to receive(:add_methods_to_model_class!).once.with(model_dmm, @model_class)

    @instance.add_delegated_methods!(flex_column_dmm, model_dmm, @model_class)
  end

  it "should call through to the fields on #include_fields_into!" do
    @field_foo = double("field_foo")
    allow(@field_foo).to receive(:json_storage_name).with().and_return(:foo)

    @field_bar = double("field_bar")
    allow(@field_bar).to receive(:json_storage_name).with().and_return(:bar)

    expect(FlexColumns::Definition::FieldDefinition).to receive(:new).once.with(@flex_column_class, :foo, [ ], { }).and_return(@field_foo)
    @instance.field(:foo)

    expect(FlexColumns::Definition::FieldDefinition).to receive(:new).once.with(@flex_column_class, :bar, [ ], { }).and_return(@field_bar)
    @instance.field(:bar)

    dmm = double("dmm")
    target_class = double("target_class")
    options = double("options")

    expect(@field_foo).to receive(:add_methods_to_included_class!).once.with(dmm, :assocname, target_class, options)
    expect(@field_bar).to receive(:add_methods_to_included_class!).once.with(dmm, :assocname, target_class, options)

    @instance.include_fields_into(dmm, :assocname, target_class, options)
  end
end
