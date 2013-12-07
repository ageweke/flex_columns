require 'flex_columns'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns compression operations" do
  include FlexColumns::Helpers::SystemHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    migrate do
      drop_table :flexcols_spec_users rescue nil
      create_table :flexcols_spec_users do |t|
        t.string :name, :null => false
        t.binary :user_attributes
      end
    end

    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :foo
        field :bar
      end
    end

    define_model_class(:UserBackdoor, 'flexcols_spec_users') { }
  end

  after :each do
    migrate do
      drop_table :flexcols_spec_users rescue nil
    end
  end

  it "should not compress short data" do
    user = ::User.new
    user.name = 'User 1'
    user.foo = 'foo1'
    user.bar = 'bar1'
    user.save!

    user_again = ::User.find(user.id)
    user_again.foo.should == 'foo1'
    user_again.bar.should == 'bar1'

    user_bd = ::UserBackdoor.find(user.id)
    data = user_bd.user_attributes
    data.should match(/foo1/)
    data.should match(/bar1/)
  end

  it "should compress long data" do
    user = ::User.new
    user.name = 'User 1'
    user.foo = 'foo' * 1000
    user.bar = 'bar1'
    user.save!

    user_again = ::User.find(user.id)
    user_again.foo.should == 'foo' * 1000
    user_again.bar.should == 'bar1'

    user_bd = ::UserBackdoor.find(user.id)
    data = user_bd.user_attributes
    data.length.should < 1000
    data.should_not match(/foo/)
    data.should_not match(/bar/)
  end

  it "should not compress long data, if asked not to" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :compress => false do
        field :foo
        field :bar
      end
    end

    user = ::User.new
    user.name = 'User 1'
    user.foo = 'foo' * 1000
    user.bar = 'bar1'
    user.save!

    user_again = ::User.find(user.id)
    user_again.foo.should == 'foo' * 1000
    user_again.bar.should == 'bar1'

    user_bd = ::UserBackdoor.find(user.id)
    data = user_bd.user_attributes
    data.length.should >= 3000
    data.should match(/foofoofoofoo/)
    data.should match(/bar1/)
  end
end
