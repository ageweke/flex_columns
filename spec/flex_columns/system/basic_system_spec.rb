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

      user = ::User.new
      user.name = 'User 1'
      user.user_attributes['wants_email'] = false
      user.save!
    end
  end
end
