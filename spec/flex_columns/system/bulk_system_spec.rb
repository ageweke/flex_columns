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

  it "should return #to_stored_data correctly on a text column, and return the exact same thing for #to_json" do
    user = ::User.new
    user.name = "User 1"
    user.aaa = "aaa#{rand(1_000_000)}"
    user.bbb = rand(1_000_000)

    json = user.user_attributes.to_stored_data
    json.class.should be(String)

    parsed = JSON.parse(json)
    parsed.keys.sort.should == %w{aaa bbb}.sort
    parsed['aaa'].should == user.aaa

    user.user_attributes.to_json.should == json
  end

  context "with a binary column" do
    before :each do
      migrate do
        drop_table :flexcols_spec_users rescue nil
        create_table :flexcols_spec_users do |t|
          t.string :name, :null => false
          t.binary :user_attributes
        end
      end

      ::User.reset_column_information

      define_model_class(:User, 'flexcols_spec_users') do
        flex_column :user_attributes do
          field :aaa, :string
          field :bbb, :integer
        end
      end
    end

    it "should return #to_stored_data correctly on a binary column, uncompressed, but return JSON separately with #to_json" do
      user = ::User.new
      user.name = "User 1"
      user.aaa = "aaa#{rand(1_000_000)}"
      user.bbb = rand(1_000_000)

      stored_data = user.user_attributes.to_stored_data
      stored_data.class.should be(String)
      stored_data.should match(/^FC:01,0,/)

      stored_data =~ /^FC:01,0,(.*)$/i
      json = $1
      parsed = JSON.parse(json)
      parsed.keys.sort.should == %w{aaa bbb}.sort
      parsed['aaa'].should == user.aaa

      user.user_attributes.to_json.should == json
    end

    it "should return #to_stored_data correctly on a binary column, compressed, but return JSON separately with #to_json" do
      user = ::User.new
      user.name = "User 1"
      user.aaa = "aaa#{rand(1_000_000)}" * 1_000
      user.bbb = rand(1_000_000)

      stored_data = user.user_attributes.to_stored_data
      stored_data.class.should be(String)
      stored_data.should match(/^FC:01,1,(.*)/)

      stored_data =~ /^FC:01,1,(.*)$/i
      compressed = $1

      require 'stringio'
      stream = StringIO.new(compressed, "r")
      reader = Zlib::GzipReader.new(stream)
      json = reader.read

      parsed = JSON.parse(json)
      parsed.keys.sort.should == %w{aaa bbb}.sort
      parsed['aaa'].should == user.aaa

      user.user_attributes.to_json.should == json
    end
  end

  it "should be able to instantiate fields without an ActiveRecord model, and then serialize them again" do
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

    json_blobs.each_with_index do |json_blob, i|
      object = ::User.create_flex_object_from(:user_attributes, json_blob)

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
