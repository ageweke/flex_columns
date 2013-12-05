require 'flex_columns'
require 'flex_columns/helpers/exception_helpers'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns validations" do
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

  it "should allow controlling which fields get delegated to the class, or with a prefix, on a field-by-field basis" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :wants_email, :delegate => false
        field :something, :delegate => { :prefix => 'foo' }
        field :something_else
      end
    end

    user = ::User.new

    user.respond_to?(:wants_email).should_not be
    lambda { user.wants_email }.should raise_error(NameError)
    user.respond_to?(:wants_email=).should_not be
    lambda { user.wants_email = "foo" }.should raise_error(NameError)

    user.user_attributes.wants_email = "foo"
    user.user_attributes.wants_email.should == "foo"

    user.respond_to?(:something).should_not be
    lambda { user.something }.should raise_error(NameError)
    user.respond_to?(:something=).should_not be
    lambda { user.something = "foo" }.should raise_error(NameError)

    user.foo_something = "bar"
    user.foo_something.should == "bar"

    user.something_else = "baz"
    user.something_else.should == "baz"

    user.user_attributes.wants_email.should == "foo"
    user.user_attributes.something.should == "bar"
    user.user_attributes.something_else.should == "baz"
  end
end
