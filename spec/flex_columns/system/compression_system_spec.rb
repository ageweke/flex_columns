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

  it "should not add a header, and should not compress data, if passed :header => false" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :header => false do
        field :foo
        field :bar
      end
    end

    user = ::User.new
    user.name = 'User 1'
    user.foo = "foo1"
    user.bar = "bar1"
    user.save!

    user_bd = ::UserBackdoor.find(user.id)
    data = user_bd.user_attributes
    parsed = JSON.parse(data)
    parsed.keys.sort.should == %w{foo bar}.sort

    user = ::User.new
    user.name = 'User 1'
    user.foo = "foo" * 10_000
    user.bar = "bar1"
    user.save!

    user_bd = ::UserBackdoor.find(user.id)
    data = user_bd.user_attributes
    data.length.should > 30_000
    parsed = JSON.parse(data)
    parsed.keys.sort.should == %w{foo bar}.sort
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

  it "should read compressed data fine, even if told not to compress new data" do
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

    define_model_class(:User2, 'flexcols_spec_users') do
      flex_column :user_attributes, :compress => false do
        field :foo
        field :bar
      end
    end

    user2 = ::User2.find(user.id)
    user.foo.should == 'foo' * 1000
    user.bar.should == 'bar1'
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

  it "should not compress data if the compressed version is bigger" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :compress => 1 do
        field :foo
        field :bar
      end
    end

    user = ::User.new
    user.name = 'User 1'
    user.foo = 'f'
    user.save!

    user_again = ::User.find(user.id)
    user_again.foo.should == 'f'
    user_again.bar.should be_nil

    user_bd = ::UserBackdoor.find(user.id)
    data = user_bd.user_attributes
    data.should match(/^FC:01,0,\{/i)
  end

  it "should not compress data under a certain limit, if asked to" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :compress => 10_000 do
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

    user2 = ::User.new
    user2.name = 'User 1'
    user2.foo = 'foo' * 10_000
    user2.bar = 'bar1'
    user2.save!

    user2_again = ::User.find(user2.id)
    user2_again.foo.should == 'foo' * 10_000
    user2_again.bar.should == 'bar1'

    user2_bd = ::UserBackdoor.find(user2.id)
    data = user2_bd.user_attributes
    data.length.should < 10_000
    data.should_not match(/foofoofoofoo/)
    data.should_not match(/bar1/)
  end
end
