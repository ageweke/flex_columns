require 'flex_columns'
require 'flex_columns/helpers/exception_helpers'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns delegation" do
  include FlexColumns::Helpers::SystemHelpers
  include FlexColumns::Helpers::ExceptionHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should delegate methods by default" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :wants_email
        field :something
        field :something_else
      end
    end

    user = ::User.new

    %w{wants_email something something_else}.each do |method_name|
      user.respond_to?(method_name).should be
      user.respond_to?("#{method_name}=").should be

      user.send(method_name).should be_nil
      value = "abc123#{rand(1_000)}"
      user.send("#{method_name}=", value).should == value
      user.send(method_name).should == value

      user.user_attributes.send(method_name).should == value
      user.user_attributes.send("#{method_name}=", value + "new").should == value + "new"
      user.send(method_name).should == value + "new"
    end
  end

  it "should let you turn off delegation for a column" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :delegate => false do
        field :wants_email
        field :something
        field :something_else
      end
    end

    user = ::User.new

    %w{wants_email something something_else}.each do |method_name|
      user.respond_to?(method_name).should_not be
      user.respond_to?("#{method_name}=").should_not be

      lambda { user.send(method_name) }.should raise_error(NoMethodError.superclass)
      lambda { user.send("#{method_name}=", 1234) }.should raise_error(NoMethodError.superclass)

      user.user_attributes.send(method_name).should be_nil
      value = "abc123#{rand(1_000)}"
      user.user_attributes.send("#{method_name}=", value).should == value
      user.user_attributes.send(method_name).should == value
    end
  end

  it "should let you use private delegation for a column" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :delegate => :private do
        field :wants_email
        field :something
        field :something_else
      end
    end

    user = ::User.new

    %w{wants_email something something_else}.each do |method_name|
      user.respond_to?(method_name).should_not be
      user.respond_to?("#{method_name}=").should_not be

      lambda { eval("user.#{method_name}") }.should raise_error(NoMethodError)
      lambda { eval("user.#{method_name} = 123") }.should raise_error(NoMethodError)

      user.send(method_name).should be_nil
      value = "abc123#{rand(1_000)}"
      user.send("#{method_name}=", value).should == value
      user.send(method_name).should == value
    end
  end

  it "should let you add a prefix to methods" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :prefix => 'bar' do
        field :wants_email
        field :something
        field :something_else
      end
    end

    user = ::User.new

    %w{wants_email something something_else}.each do |method_name|
      user.respond_to?(method_name).should_not be
      user.respond_to?("#{method_name}=").should_not be

      lambda { user.send(method_name) }.should raise_error(NoMethodError.superclass)
      lambda { user.send("#{method_name}=", 1234) }.should raise_error(NoMethodError.superclass)

      correct_method_name = "bar_#{method_name}"
      user.respond_to?(correct_method_name).should be
      user.respond_to?("#{correct_method_name}=").should be

      user.send(correct_method_name).should be_nil
      value = "abc123#{rand(1_000)}"
      user.send("#{correct_method_name}=", value).should == value
      user.send(correct_method_name).should == value

      user.user_attributes.send(method_name).should == value
      user.user_attributes.send("#{method_name}=", value + "new").should == value + "new"
      user.send(correct_method_name).should == value + "new"
    end
  end
end
