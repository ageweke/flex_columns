require 'flex_columns'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns validations" do
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
    it "should allow validating fields in the column definition" do
      define_model_class(:User, 'flexcols_spec_users') do
        flex_column :user_attributes do
          field :wants_email

          validates :wants_email, :presence => true
        end
      end

      user = ::User.new
      user.name = 'User 1'

      lambda { user.save! }.should raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
