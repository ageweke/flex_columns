require 'flex_columns'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns unknown fields" do
  include FlexColumns::Helpers::SystemHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!

    define_model_class(:UserBackdoor, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :wants_email
        field :some_unknown_attribute
      end
    end

    @user_bd = ::UserBackdoor.new
    @user_bd.name = 'User 1'
    @user_bd.some_unknown_attribute = 'bongo'
    @user_bd.save!
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should preserve unknown fields by default" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :wants_email
      end
    end

    user = ::User.find(@user_bd.id)
    user.name.should == 'User 1'
    user.wants_email.should be_nil
    user.wants_email = 'does_want'

    user.respond_to?(:some_unknown_attribute).should_not be
    lambda { user.send(:some_unknown_attribute) }.should raise_error(NoMethodError)
    lambda { user.user_attributes[:some_unknown_attribute] }.should raise_error(FlexColumns::Errors::NoSuchFieldError)
    lambda { user.user_attributes[:some_unknown_attribute] = 123 }.should raise_error(FlexColumns::Errors::NoSuchFieldError)

    user.save!

    user_bd_again = ::UserBackdoor.find(@user_bd.id)
    user_bd_again.wants_email.should == 'does_want'
    user_bd_again.some_unknown_attribute.should == 'bongo'
  end

  it "should delete unknown fields if asked to" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :unknown_fields => :delete do
        field :wants_email
      end
    end

    user = ::User.find(@user_bd.id)
    user.name.should == 'User 1'
    user.wants_email.should be_nil
    user.wants_email = 'does_want'

    user.respond_to?(:some_unknown_attribute).should_not be
    lambda { user.send(:some_unknown_attribute) }.should raise_error(NoMethodError)
    lambda { user.user_attributes[:some_unknown_attribute] }.should raise_error(FlexColumns::Errors::NoSuchFieldError)
    lambda { user.user_attributes[:some_unknown_attribute] = 123 }.should raise_error(FlexColumns::Errors::NoSuchFieldError)

    user.save!

    user_bd_again = ::UserBackdoor.find(@user_bd.id)
    user_bd_again.wants_email.should == 'does_want'
    user_bd_again.some_unknown_attribute.should be_nil
  end

  it "should have a method that explicitly will purge unknown methods, even if deserialization hasn't happened for any other reason, but not before then" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :unknown_fields => :delete do
        field :wants_email
      end
    end

    user = ::User.find(@user_bd.id)
    user.save!

    user_bd_again = ::UserBackdoor.find(@user_bd.id)
    user_bd_again.wants_email.should be_nil
    user_bd_again.some_unknown_attribute.should == 'bongo'

    user = ::User.find(@user_bd.id)
    user.user_attributes.touch!
    user.save!

    user_bd_again = ::UserBackdoor.find(@user_bd.id)
    user_bd_again.wants_email.should be_nil
    user_bd_again.some_unknown_attribute.should be_nil
  end
end
