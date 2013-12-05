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
      user2.user_attributes.keys.should == [ :wants_email ]
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
      contents.keys.should == [ 'wants_email' ]
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
      user2.user_attributes.keys.should == [ :wants_email ]
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
      user2.user_attributes.keys.should == [ :wants_email ]
    end

    it "should have a reasonable class name for contents" do
      class_name = ::User.new.user_attributes.class.name
      class_name.should match(/^user::/i)
      class_name.should match(/userattributes/i)
      class_name.should match(/flexcolumn/i)
    end

    it "should let you redefine flex columns, and obey the new settings"
    it "should let you change the attribute name of a flex column to be different from the column itself, if you want"
    it "should let you make flex-column accessors private, if you want"
    it "should return a nice error if JSON parsing fails"
    it "should return a nice error if the string isn't even a validly-encoded string"
    it "should allow making the flex-column name in the code different from the actual column name in the table"
    it "should fail before storing if the JSON produced is too long for the column"
    it "should discard all attributes when #reload is called"
    it "should not deserialize columns if they aren't touched"
    it "should not deserialize columns to run validations if there aren't any"
    it "should deserialize columns to run validations if there are any"
    it "should delete undefined attributes from JSON data if asked to, if a field is touched"
    it "should not delete undefined attributes from JSON data if not asked to"
    it "should allow marking fields as preserved, so you can't access them but they aren't deleted"
    it "should allow generating methods as private if requested"
  end
end
