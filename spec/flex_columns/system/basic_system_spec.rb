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

  context "with a very simple column definition" do
    before :each do
      define_model_class(:User, 'flexcols_spec_users') do
        flex_column :user_attributes do
          field :wants_email
        end
      end
    end

    it "should be able to serialize and deserialize a very simple example" do
      define_model_class(:UserBackdoor, 'flexcols_spec_users') { }

      user = ::User.new
      user.name = 'User 1'
      user.user_attributes['wants_email'] = 'sometimes'
      user.user_attributes['wants_email'].should == 'sometimes'
      user.save!

      user.user_attributes['wants_email'].should == 'sometimes'

      user2 = ::User.find(user.id)
      user2.user_attributes['wants_email'].should == 'sometimes'
      user2.user_attributes.keys.should == %w{wants_email}
    end

    it "should store its data as standard JSON" do
      user = ::User.new
      user.name = 'User 1'
      user.user_attributes['wants_email'] = 'sometimes'
      user.save!

      bd = ::UserBackdoor.find(user.id)
      bd.should be
      bd.id.should == user.id

      string = bd.user_attributes
      string.should be
      string.length.should > 0

      contents = JSON.parse(string)
      contents.class.should == Hash
      contents.keys.should == %w{wants_email}
      contents['wants_email'].should == 'sometimes'
    end

    it "should provide access to attributes as methods" do
      user = ::User.new
      user.name = 'User 1'
      user.user_attributes.wants_email = 'sometimes'
      user.user_attributes.wants_email.should == 'sometimes'
      user.user_attributes['wants_email'].should == 'sometimes'
      user.save!

      user.user_attributes.wants_email.should == 'sometimes'

      user2 = ::User.find(user.id)
      user2.user_attributes.wants_email.should == 'sometimes'
      user2.user_attributes.keys.should == %w{wants_email}
    end

    it "should delegate methods to attributes automatically" do
      user = ::User.new
      user.name = 'User 1'
      user.wants_email = 'sometimes'
      user.wants_email.should == 'sometimes'
      user.user_attributes['wants_email'].should == 'sometimes'
      user.save!

      user.wants_email.should == 'sometimes'

      user2 = ::User.find(user.id)
      user2.wants_email.should == 'sometimes'
      user2.user_attributes.keys.should == %w{wants_email}
    end

    it "should have a reasonable class name for contents" do
      class_name = ::User.new.user_attributes.class.name
      class_name.should match(/^user::/i)
      class_name.should match(/userattributes/i)
      class_name.should match(/flexcontents/i)
    end
  end
end
