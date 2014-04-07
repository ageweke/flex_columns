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

    it "shouldn't complain if there is no data, but you still touch a field" do
      user = ::User.new
      user.name = 'User 1'
      user.user_attributes.wants_email
      user.save!
    end

    # This test case was created from a found bug: we were assuming that unless you called "#{method}=" on one of
    # the attributes of a flex column, then we didn't need to serialize and save the flex column. However, that's not
    # true, for exactly the reasons seen below (maybe you modified an object that was referred to from the field,
    # but didn't change that field itself). See also the comment above ColumnData#deserialized?.
    it "should still save its data even if you change something nested down deep" do
      user = ::User.new
      user.name = 'User 1'
      user.user_attributes.wants_email = { 'foo' => { 'bar' => [ 1, 2, 3 ] } }
      user.save!

      user_again = ::User.find(user.id)
      user_again.user_attributes.wants_email['foo']['bar'] << 4
      user_again.save!

      user_yet_again = ::User.find(user.id)
      user_yet_again.user_attributes.wants_email['foo']['bar'].should == [ 1, 2, 3, 4 ]
    end

    it "should return useful data for the column on #inspect, deserializing if necessary" do
      user = ::User.new
      user.name = 'User 1'
      user.wants_email = 'whatEVER, yo'
      user.save!

      user_again = ::User.find(user.id)
      s = user_again.user_attributes.inspect
      s.should match(/UserAttributesFlexContents/i)
      s.should match(/wants_email/i)
      s.should match(/whatEVER, yo/)
    end

    it "should return useful data for the column on #inspect from the parent AR model" do
      user = ::User.new
      user.name = 'User 1'
      user.wants_email = 'whatEVER, yo'
      user.save!

      user_again = ::User.find(user.id)
      s = user_again.inspect
      s.should match(/UserAttributesFlexContents/i)
      s.should match(/wants_email/i)
      s.should match(/whatEVER, yo/)
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

    it "should not modify that JSON if you don't touch it, but should if you do" do
      define_model_class(:UserBackdoor, 'flexcols_spec_users') { }

      weirdly_spaced_json = '   {        "wants_email"  : "boop"    } '

      user_bd = ::UserBackdoor.new
      user_bd.name = 'User 1'
      user_bd.user_attributes = weirdly_spaced_json
      user_bd.save!

      user = ::User.find(user_bd.id)
      user.name.should == 'User 1'
      user.wants_email
      user.save!

      user_bd_again = ::UserBackdoor.find(user_bd.id)
      user_bd_again.name.should == 'User 1'
      user_bd_again.user_attributes.should == '{"wants_email":"boop"}'
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

    it "should allow you to call #reload, and return that same record" do
      user = ::User.new
      user.name = 'User 1'
      user.wants_email = [ 1, 2, 3 ]
      user.save!

      user.name = 'User 2'
      user.wants_email = 'bonko'

      new_user = user.reload
      new_user.name.should == 'User 1'
      new_user.wants_email.should == [ 1, 2, 3 ]
      new_user.id.should == user.id

      user.name.should == 'User 1'
      user.wants_email.should == [ 1, 2, 3 ]

      new_user.should be(user)
    end

    # JSON.dump() simply doesn't work at all with ActiveRecord objects in earlier ActiveRecord versions; see:
    # http://stackoverflow.com/questions/8406924/json-dump-on-any-activerecord-object-fails
    if ActiveRecord::VERSION::MAJOR >= 4 ||
      (ActiveRecord::VERSION::MAJOR == 3 && ActiveRecord::VERSION::MINOR >= 1)
      it "should let you turn an entire ActiveRecord object into JSON properly, treating a flex column as a Hash" do
        user = ::User.new
        user.id = 12345
        user.name = 'User 1'
        user.wants_email = [ 1, 2, 3 ]

        $stderr.puts "ATTRIBUTES: #{user.attributes.keys.sort.inspect}"

        user_json = JSON.dump(user)
        parsed = JSON.parse(user_json)

        # ActiveRecord::Base.include_root_in_json may default to different things in different versions of
        # ActiveRecord; here, we accept JSON in either format.
        base = parsed
        base = parsed['user'] if base.keys == %w{user}

        base.keys.sort.should == %w{id name user_attributes more_attributes}.sort
        base['id'].should == 12345
        base['name'].should == 'User 1'
        h = base['user_attributes']
        h.class.should == Hash
        h.keys.sort.should == %w{wants_email}
        h['wants_email'].should == [ 1, 2, 3 ]
        [ nil, { } ].include?(base['more_attributes']).should be
      end
    end

    it "should remove keys entirely when they're set to nil, but not if they're set to false" do
      define_model_class(:User, 'flexcols_spec_users') do
        flex_column :user_attributes do
          field :aaa
          field :bbb
        end
      end
      define_model_class(:UserBackdoor, 'flexcols_spec_users') { }

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

    it "should allow serializing Float::INFINITY and Float::NaN" do
      infinity = if defined?(Float::INFINITY) then Float::INFINITY else (1.0 / 0.0) end
      nan = if defined?(Float::NaN) then Float::NaN else (0.0 / 0.0) end

      user = ::User.new
      user.name = 'User 1'
      user.wants_email = { 'foo' => 'bar', 'bar' => infinity, 'baz' => nan, 'quux' => -infinity }
      user.save!

      user_again = ::User.find(user.id)
      user_again.wants_email['foo'].should == 'bar'
      user_again.wants_email['bar'].should == infinity
      user_again.wants_email['baz'].should be_nan
      user_again.wants_email['quux'].should == -infinity
    end
  end
end
