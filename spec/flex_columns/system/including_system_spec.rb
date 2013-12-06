require 'flex_columns'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns including" do
  include FlexColumns::Helpers::SystemHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!

    migrate do
      drop_table :flexcols_spec_user_preferences rescue nil
      create_table :flexcols_spec_user_preferences, :id => false do |t|
        t.integer :user_id, :null => false
        t.text :attribs1
        t.text :attribs2
      end

      add_index :flexcols_spec_user_preferences, :user_id, :unique => true
    end

    define_model_class(:UserPreference, 'flexcols_spec_user_preferences') do
      self.primary_key = :user_id

      belongs_to :user

      flex_column :attribs1 do
        field :foo
        field :bar
      end
    end
  end

  after :each do
    drop_standard_system_spec_tables!

    migrate do
      drop_table :flexcols_spec_user_preferences rescue nil
    end
  end

  it "should include columns appropriately" do
    define_model_class(:User, 'flexcols_spec_users') do
      has_one :preference, :class_name => 'UserPreference'

      include_flex_columns_from :preference
    end

    user = ::User.new
    user.name = 'User 1'

    user.foo = 'foo1'
    user.bar = 'bar1'

    user.save!

    user_again = ::User.find(user.id)
    user_again.foo.should == 'foo1'
    user_again.bar.should == 'bar1'

    preferences = ::UserPreference.find(user.id)
    preferences.foo.should == 'foo1'
    preferences.bar.should == 'bar1'
  end

  it "should include columns privately, if requested" do
    define_model_class(:User, 'flexcols_spec_users') do
      has_one :preference, :class_name => 'UserPreference'

      include_flex_columns_from :preference, :visibility => :private
    end

    user = ::User.new
    user.name = 'User 1'

    user.respond_to?(:foo).should_not be
    user.respond_to?(:foo=).should_not be
    user.respond_to?(:bar).should_not be
    user.respond_to?(:bar=).should_not be

    lambda { user.foo }.should raise_error(NoMethodError)
    lambda { user.foo = 123 }.should raise_error(NoMethodError)
    lambda { user.bar }.should raise_error(NoMethodError)
    lambda { user.bar = 123 }.should raise_error(NoMethodError)

    user.send(:foo=, 'foo1').should == 'foo1'
    user.send(:bar=, 'bar1').should == 'bar1'

    user.save!

    user_again = ::User.find(user.id)
    user_again.send(:foo).should == 'foo1'
    user_again.send(:bar).should == 'bar1'

    preferences = ::UserPreference.find(user.id)
    preferences.foo.should == 'foo1'
    preferences.bar.should == 'bar1'
  end

  it "should prefix included method names, if requested" do
    define_model_class(:User, 'flexcols_spec_users') do
      has_one :preference, :class_name => 'UserPreference'

      include_flex_columns_from :preference, :prefix => 'abc'
    end

    user = ::User.new
    user.name = 'User 1'

    lambda { user.send(:foo) }.should raise_error(NoMethodError)
    lambda { user.send(:foo=, 123) }.should raise_error(NoMethodError)
    lambda { user.send(:bar) }.should raise_error(NoMethodError)
    lambda { user.send(:bar=, 123) }.should raise_error(NoMethodError)

    user.abc_foo = 'foo1'
    user.abc_bar = 'bar1'

    user.save!

    user_again = ::User.find(user.id)
    user_again.abc_foo.should == 'foo1'
    user_again.abc_bar.should == 'bar1'

    preferences = ::UserPreference.find(user.id)
    preferences.foo.should == 'foo1'
    preferences.bar.should == 'bar1'
  end
end
