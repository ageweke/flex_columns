require 'flex_columns'

describe FlexColumns::ActiveRecord::Base do
  before :each do
    @klass = Class.new
    @klass.send(:include, FlexColumns::ActiveRecord::Base)
  end

  it "should say #has_any_flex_columns? is false by default" do
    @klass.has_any_flex_columns?.should_not be
  end

  it "should include HasFlexColumns on flex_column" do
    block = lambda { "hi!" }

    expect(@klass).to receive(:include).once.with(FlexColumns::HasFlexColumns) do
      expect(@klass).to receive(:flex_column).once.with(:foo, &block)
    end

    @klass.flex_column(:foo, &block).should == "hi!"
  end

  it "should include IncludeFlexColumns on include_flex_columns_from" do
    block = lambda { "hi!" }

    expect(@klass).to receive(:include).once.with(FlexColumns::Including::IncludeFlexColumns) do
      expect(@klass).to receive(:include_flex_columns_from).once.with(:foo, &block)
    end

    @klass.include_flex_columns_from(:foo, &block).should == "hi!"
  end
end
