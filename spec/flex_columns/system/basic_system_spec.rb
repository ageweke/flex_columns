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
      class_name.should match(/flexcontents/i)
    end

    it "should let you make flex-column accessors private one-by-one" do
      define_model_class(:User, 'flexcols_spec_users') do
        flex_column :user_attributes do
          field :wants_email, :visibility => :private
          field :another_thing
        end
      end

      user = ::User.new
      user.user_attributes.respond_to?(:wants_email).should_not be
      lambda { user.user_attributes.wants_email }.should raise_error(NoMethodError)

      user.user_attributes.send(:wants_email).should be_nil
      user.user_attributes.send("wants_email=", "foobar").should == "foobar"
      user.user_attributes.send(:wants_email).should == "foobar"

      user.user_attributes.another_thing = 123
      user.user_attributes.another_thing.should == 123

      user.respond_to?(:wants_email).should_not be
      user.respond_to?(:another_thing).should be
    end

    it "should let you make flex-column accessors private en masse, and override it one-by-one" do
      define_model_class(:User, 'flexcols_spec_users') do
        flex_column :user_attributes, :visibility => :private do
          field :wants_email
          field :another_thing, :visibility => :public
        end
      end

      user = ::User.new
      user.user_attributes.respond_to?(:wants_email).should_not be
      lambda { user.user_attributes.wants_email }.should raise_error(NoMethodError)

      user.user_attributes.send(:wants_email).should be_nil
      user.user_attributes.send("wants_email=", "foobar").should == "foobar"
      user.user_attributes.send(:wants_email).should == "foobar"

      user.user_attributes.another_thing = 123
      user.user_attributes.another_thing.should == 123

      user.respond_to?(:wants_email).should_not be
      user.respond_to?(:another_thing).should be
    end

    it "should return Symbols as Strings, so that saving to the database and reading from it doesn't produce a different result (since Symbols are stored in JSON as Strings)" do
      user = ::User.new
      user.name = 'User 1'
      user.wants_email = :bonko
      user.wants_email.should == 'bonko'
      user.save!

      user_again = ::User.find(user.id)
      user_again.wants_email.should == 'bonko'
    end

    it "should allow storing an Array happily" do
      user = ::User.new
      user.name = 'User 1'
      user.wants_email = [ 123, "foo", 47.2, { 'foo' => 'bar' } ]
      user.save!

      user_again = ::User.find(user.id)
      user_again.wants_email.should == [ 123, 'foo', 47.2, { 'foo' => 'bar' } ]
    end

    it "should allow storing a Hash happily" do
      user = ::User.new
      user.name = 'User 1'
      user.wants_email = { 'foo' => 47.2, '13' => 'bar', 'baz' => [ 'a', 'b', 'c' ] }
      user.save!

      user_again = ::User.find(user.id)
      output = user_again.wants_email
      output.class.should == Hash
      output.keys.sort.should == [ '13', 'baz', 'foo' ].sort
      output['13'].should == 'bar'
      output['baz'].should == [ 'a', 'b', 'c' ]
      output['foo'].should == 47.2
    end

    it "should remove keys entirely when they're set to nil, but not if they're set to false" do
      define_model_class(:User, 'flexcols_spec_users') do
        flex_column :user_attributes do
          field :aaa
          field :bbb
        end
      end

      ::User.reset_column_information

      user = ::User.new
      user.name = 'User 1'
      user.aaa = 'aaa1'
      user.bbb = 'bbb1'
      user.save!

      user_bd = ::UserBackdoor.find(user.id)
      JSON.parse(user_bd.user_attributes).keys.sort.should == %w{aaa bbb}.sort

      user.aaa = false
      user.save!

      user_bd = ::UserBackdoor.find(user.id)
      parsed = JSON.parse(user_bd.user_attributes)
      parsed.keys.sort.should == %w{aaa bbb}.sort
      parsed['aaa'].should == false

      user.aaa = nil
      user.save!

      user_bd = ::UserBackdoor.find(user.id)
      parsed = JSON.parse(user_bd.user_attributes)
      parsed.keys.sort.should == %w{bbb}.sort
    end
  end
end
