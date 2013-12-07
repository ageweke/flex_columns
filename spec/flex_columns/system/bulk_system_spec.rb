require 'flex_columns'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns bulk operations" do
  include FlexColumns::Helpers::SystemHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  before :each do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :aaa, :string
        field :bbb, :integer
      end
    end
  end

  it "should be able to instantiate fields without an ActiveRecord model" do
    users = [ ]
    10.times do |i|
      user = ::User.new
      user.name = "User #{i}"
      user.aaa = "aaa#{rand(1_000_000)}"
      user.bbb = rand(1_000_000)
      user.save!

      users << user
    end

    json_blobs = [ ]
    ::User.connection.select_all("SELECT id, user_attributes FROM flexcols_spec_users ORDER BY id ASC").each do |row|
      json_blobs << row['user_attributes']
    end

    as_objects = ::User.create_flex_objects_from(:user_attributes, json_blobs)
    as_objects.each_with_index do |object, i|
      user = users[i]

      object.aaa.should == user.aaa
      object.bbb.should == user.bbb

      object.bbb = "cannot-validate"
      object.valid?.should_not be
      object.errors.keys.should == [ :bbb ]
      object.errors[:bbb].length.should == 1
      object.errors[:bbb][0].should match(/is not a number/i)
    end
  end
end
