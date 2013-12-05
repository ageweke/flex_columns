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

  it "should allow picking up flex-column attributes from a whole different class, and it should save appropriately" do
    define_model_class(:UserDetails, 'flexcols_spec_user_details_1') do
      flex_column :attributes_1a do
        field :att1a_f1
        field :att1a_f2
      end

      flex_column :attributes_1b do
        field :att1b_f1
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
    user.att1a_f1.should == "foo"

    user.att1a_f2 = "bar"
    user.att1a_f2.should == "bar"
    user.attributes_1a.att1a_f2.should == "bar"

    user.att1b_f1 = "baz"
    user.att1b_f1.should == "baz"
    user.attributes_1b.att1b_f1.should == "baz"

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
    h.keys.sort.should == [ 'att1a_f1', 'att1a_f2' ].sort
    h['att1a_f1'].should == 'foo'
    h['att1a_f2'].should == 'bar'

    s = bd_details.attributes_1b
    s.should be
    s.length.should > 0

    h = JSON.parse(s)
    h.keys.should == [ 'att1b_f1' ]
    h['att1b_f1'].should == 'baz'
  end

  it "should allow delegating only certain columns" do
    define_model_class(:UserDetails, 'flexcols_spec_user_details_1') do
      flex_column :attributes_1a do
        field :att1a_f1
      end

      flex_column :attributes_1b do
        field :att1b_f1
      end

      belongs_to :user
    end

    define_model_class(:User, 'flexcols_spec_users') do
      has_one :user_details

      include_flex_columns_from :user_details, :columns => [ :attributes_1a ]
    end

    user = ::User.new
    user.name = 'User 1'

    user.att1a_f1 = "foo"
    user.att1a_f1.should == "foo"

    user.respond_to?(:attributes_1b).should_not be
    user.respond_to?(:att1b_f1).should_not be
    user.respond_to?(:att1b_f1=).should_not be
    lambda { user.attributes_1b }.should raise_error(NameError)
    lambda { user.att1b_f1 }.should raise_error(NameError)
    lambda { user.att1b_f1 = "foo" }.should raise_error(NameError)
  end

  it "should allow prefixing delegated names" do
    define_model_class(:UserDetails, 'flexcols_spec_user_details_1') do
      flex_column :attributes_1a do
        field :att1a_f1
      end

      flex_column :attributes_1b, :delegate => { :prefix => 'bonk' } do
        field :att1b_f1
      end

      belongs_to :user
    end

    define_model_class(:User, 'flexcols_spec_users') do
      has_one :user_details

      include_flex_columns_from :user_details, :prefix => 'abc'
    end

    user = ::User.new
    user.name = 'User 1'

    user.respond_to?(:attributes_1a).should_not be
    user.respond_to?(:att1a_f1).should_not be
    user.respond_to?(:att1a_f1=).should_not be

    lambda { user.attributes_1a }.should raise_error(NameError)
    lambda { user.att1a_f1 }.should raise_error(NameError)
    lambda { user.att1a_f1 = "foo" }.should raise_error(NameError)

    user.abc_att1a_f1 = "foo"
    user.abc_att1a_f1.should == "foo"
    user.abc_attributes_1a.att1a_f1.should == "foo"

    user.abc_attributes_1b.att1b_f1 = "bar"
    user.abc_attributes_1b.att1b_f1.should == "bar"

    user.respond_to?(:att1b_f1).should_not be
    lambda { user.att1b_f1 }.should raise_error(NameError)
    lambda { user.att1b_f1 = "x" }.should raise_error(NameError)

    user.abc_bonk_att1b_f1.should == "bar"
    user.abc_bonk_att1b_f1 = "baz"
    user.abc_bonk_att1b_f1.should == "baz"
    user.abc_attributes_1b.att1b_f1.should == "baz"
  end

  it "should not delegate fields that aren't delegated in the flex-column definition" do
    define_model_class(:UserDetails, 'flexcols_spec_user_details_1') do
      flex_column :attributes_1a do
        field :att1a_f1, :delegate => false
        field :att1a_f2
      end

      flex_column :attributes_1b, :delegate => false do
        field :att1b_f1
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
    user.att1a_f2 = "bar"
    user.attributes_1a.att1a_f2.should == "bar"

    user.respond_to?(:att1a_f1).should_not be
    lambda { user.att1a_f1 }.should raise_error(NameError)

    user.attributes_1b.att1b_f1 = "baz"
    user.attributes_1b.att1b_f1.should == "baz"

    user.respond_to?(:att1b_f1).should_not be
    lambda { user.att1b_f1 }.should raise_error(NameError)
  end

  it "should not delegate fields if asked not to"
end
