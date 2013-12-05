require 'flex_columns'
require 'flex_columns/helpers/exception_helpers'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns table-to-table delegation" do
  include FlexColumns::Helpers::SystemHelpers
  include FlexColumns::Helpers::ExceptionHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!

    migrate do
      drop_table :flexcols_spec_user_details_1 rescue nil
      create_table :flexcols_spec_user_details_1 do |t|
        t.integer :user_id, :null => false
        t.text :attributes_1a
        t.text :attributes_1b
      end

      drop_table :flexcols_spec_user_details_2 rescue nil
      create_table :flexcols_spec_user_details_2 do |t|
        t.integer :user_id, :null => false
        t.text :attributes_2
      end
    end
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should allow picking up flex-column attributes from a whole different class" do
    define_model_class(:UserDetails, 'flexcols_spec_user_details_1') do
      flex_column :attributes_1a do
        field :conflict1
        field :att1a_f1
        field :att1a_f2
      end

      flex_column :attributes_1b do
        field :att1b_f1
        field :att1b_f2
      end

      belongs_to :user
    end

    define_model_class(:User, 'flexcols_spec_users') do
      has_one :user_details

      include_flex_columns_from :user_details
    end

    user = ::User.new
    user.name = 'User 1'
    user.attributes_1a.att1a_f1 = "foo"
    user.attributes_1a.att1a_f1.should == "foo"
    user.save!

    define_model_class(:UserBackdoor, "flexcols_spec_users") { }
    define_model_class(:UserDetailsBackdoor, "flexcols_spec_user_details_1") { }

    bd_user = ::UserBackdoor.find(user.id)
    bd_user.should be

    bd_details_array = ::UserDetailsBackdoor.where(:user_id => bd_user.id).all
    bd_details_array.length.should == 1
    bd_details = bd_details_array[0]

    bd_details.should be
    bd_details.user_id.should == bd_user.id
    s = bd_details.attributes_1a
    s.should be
    s.length.should > 0

    h = JSON.parse(s)
    h.keys.should == [ 'att1a_f1' ]
  end
end
