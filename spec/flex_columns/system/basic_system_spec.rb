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

  describe "#flex_column" do
    it "should do something" do
      define_model_class(:User, 'flexcols_spec_users') do
        flex_column :user_attributes do
          field :wants_email
        end
      end

      define_model_class(:UserBackdoor, 'flexcols_spec_users') { }

      user = ::User.new
      user.name = 'User 1'
      user.user_attributes['wants_email'] = 'sometimes'
      user.user_attributes['wants_email'].should == 'sometimes'
      user.save!

      user.user_attributes['wants_email'].should == 'sometimes'

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

      user2 = ::User.find(user.id)
      user2.user_attributes['wants_email'].should == 'sometimes'
      user2.user_attributes.keys.should == %w{wants_email}
    end
  end
end
