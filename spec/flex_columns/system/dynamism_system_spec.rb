require 'flex_columns'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns basic operations" do
  include FlexColumns::Helpers::SystemHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should not blow up if the underlying table doesn't exist" do
    class ::Foo < ::ActiveRecord::Base
      self.table_name = 'flexcols_does_not_exist'

      flex_column :foo do
        field :att1
        field :att2
      end
    end
  end

  it "should let you redefine flex columns, and obey the new settings" do
    class ::User < ::ActiveRecord::Base
      self.table_name = 'flexcols_spec_users'

      flex_column :user_attributes do
        field :att1
        field :att2

        def abc
          "abc!"
        end
      end
    end

    user = ::User.new
    user.att1 = "foo"
    user.att2 = "bar"
    user.abc.should == 'abc!'

    class ::User < ::ActiveRecord::Base
      self.table_name = 'flexcols_spec_users'

      flex_column :user_attributes do
        field :att3
        field :att2

        def def
          "def!"
        end
      end
    end

    user2 = ::User.new
    user2.respond_to?(:att1).should_not be
    user2.user_attributes.respond_to?(:att1).should_not be
    user2.respond_to?(:abc).should_not be
    user2.user_attributes.respond_to?(:abc).should_not be

    # explicitly not testing if user.respond_to?(:att3) or if user.respond_to?)(:att1); we make no guarantees about
    # what happened on older objects

    class ::User < ::ActiveRecord::Base
      self.table_name = 'flexcols_spec_users'

      flex_column :user_attributes do
        field :att1
        field :att2
      end
    end

    user3 = ::User.new
    user3.respond_to?(:att1).should be
    user3.user_attributes.respond_to?(:att1).should be
    user3.respond_to?(:att2).should be
    user3.user_attributes.respond_to?(:att2).should be
    user3.user_attributes.respond_to?(:abc).should_not be
    user3.respond_to?(:abc).should_not be
    user3.user_attributes.respond_to?(:def).should_not be
    user3.respond_to?(:def).should_not be
  end

  it "should discard all attributes when #reload is called" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :wants_email
      end
    end

    user = ::User.new
    user.name = 'User 1'
    user.save!

    user = ::User.find(user.id)
    user.name = 'User 2'
    user.wants_email = 'bonko'

    user.reload

    user.name.should == 'User 1'
    user.wants_email.should be_nil
  end

  it "should use the most-recently-defined flex-column attribute in delegation, if there's a conflict" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :att1
        field :att2
      end

      flex_column :more_attributes do
        field :att2
        field :att3
      end
    end

    user = ::User.new
    user.name = 'User 1'
    user.att1 = "foo"
    user.att2 = "bar"
    user.att3 = "baz"

    user.user_attributes.att1.should == "foo"
    user.user_attributes.att2.should be_nil
    user.user_attributes.att2 = "quux"
    user.more_attributes.att2.should == "bar"
    user.more_attributes.att3.should == "baz"

    user.att2.should == "bar"

    # Now, reverse them

    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :more_attributes do
        field :att2
        field :att3
      end

      flex_column :user_attributes do
        field :att1
        field :att2
      end
    end

    user = ::User.new
    user.name = 'User 1'
    user.att1 = "foo"
    user.att2 = "bar"
    user.att3 = "baz"

    user.user_attributes.att1.should == "foo"
    user.user_attributes.att2.should == "bar"
    user.more_attributes.att2.should be_nil
    user.more_attributes.att2 = "quux"
    user.more_attributes.att3.should == "baz"

    user.user_attributes.att2.should == "bar"
    user.more_attributes.att2.should == "quux"

    user.att2.should == "bar"
  end
end
