require 'flex_columns'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns performance" do
  include FlexColumns::Helpers::SystemHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!

    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :wants_email
      end
    end

    @deserializations = [ ]
    @serializations = [ ]

    ds = @deserializations
    s = @serializations

    ActiveSupport::Notifications.subscribe('flex_columns.deserialize') do |name, start, finish, id, payload|
      ds << payload
    end

    ActiveSupport::Notifications.subscribe('flex_columns.serialize') do |name, start, finish, id, payload|
      s << payload
    end
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should fire a notification when deserializing and serializing" do
    user = ::User.new
    user.name = 'User 1'
    user.wants_email = 'foo'

    @serializations.length.should == 0
    user.save!

    @serializations.length.should == 1
    @serializations[0].class.should == Hash
    @serializations[0].keys.sort_by(&:to_s).should == [ :model_class, :model, :column_name ].sort_by(&:to_s)
    @serializations[0][:model_class].should be(::User)
    @serializations[0][:model].should be(user)
    @serializations[0][:column_name].should == :user_attributes

    user_again = ::User.find(user.id)

    @deserializations.length.should == 0
    user_again.wants_email.should == 'foo'
    @deserializations.length.should == 1
    @deserializations[0].class.should == Hash
    @deserializations[0].keys.sort_by(&:to_s).should == [ :model_class, :model, :column_name, :raw_data ].sort_by(&:to_s)
    @deserializations[0][:model_class].should be(::User)
    @deserializations[0][:model].should be(user_again)
    @deserializations[0][:column_name].should == :user_attributes
    @deserializations[0][:raw_data].should == user_again.user_attributes.to_json
  end

  it "should not deserialize columns if they aren't touched" do
    user = ::User.new
    user.name = 'User 1'
    user.wants_email = 'foo'
    user.save!

    user_again = ::User.find(user.id)
    user_again.user_attributes.should be

    @deserializations.length.should == 0
  end

  it "should not deserialize columns to run validations if there aren't any" do
    user = ::User.new
    user.name = 'User 1'
    user.wants_email = 'foo'
    user.save!

    user_again = ::User.find(user.id)
    user_again.user_attributes.should be
    user_again.valid?.should be
    user_again.user_attributes.valid?.should be

    @deserializations.length.should == 0
  end

  it "should deserialize columns to run validations if there are any" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :wants_email, :integer
      end
    end

    user = ::User.new
    user.name = 'User 1'
    user.wants_email = 12345
    user.save!

    user_again = ::User.find(user.id)
    user_again.user_attributes.should be

    @deserializations.length.should == 0

    user_again.valid?.should be
    user_again.user_attributes.valid?.should be

    @deserializations.length.should == 1
  end

  context "with NULLable and non-NULLable text and binary columns" do
    def check_text_column_data(text_data, key, value)
      parsed = JSON.parse(text_data)
      parsed.keys.should == [ key.to_s ]
      parsed[key.to_s].should == value
    end

    def check_binary_column_data(binary_data, key, value)
      if binary_data =~ /^FC:01,0,/
        without_header = binary_data[8..-1]
        parsed = JSON.parse(without_header)
        parsed.keys.should == [ key.to_s ]
        parsed[key.to_s].should == value
      end
    end

    before :each do
      migrate do
        drop_table :flexcols_spec_users rescue nil
        create_table :flexcols_spec_users do |t|
          t.string :name, :null => false
          t.text :text_attrs_nonnull, :null => false
          t.text :text_attrs_null
          t.binary :binary_attrs_nonnull, :null => false
          t.binary :binary_attrs_null
        end
      end

      ::User.reset_column_information

      define_model_class(:User, 'flexcols_spec_users') do
        flex_column :text_attrs_nonnull do
          field :aaa
        end
        flex_column :text_attrs_null do
          field :bbb
        end
        flex_column :binary_attrs_nonnull do
          field :ccc
        end
        flex_column :binary_attrs_null do
          field :ddd
        end
      end

      define_model_class(:UserBackdoor, 'flexcols_spec_users') { }

      ::UserBackdoor.reset_column_information
    end

    it "should be smart enough to store an empty JSON string to the database, if necessary, if the column is non-NULL" do
      # JRuby with the ActiveRecord-JDB adapter and MySQL seems to have the following issue: if you define a column as
      # non-NULL, and create a new model instance, then ask that model instance for the value of that column, you get
      # back empty string (""), not nil. Yet when trying to save that instance, you get an exception because it's not
      # specifying that column at all. Only setting that column to a string with spaces in it (or something else) works,
      # not even just setting it to the empty string again; as such, we're just going to give up on this example under
      # those circumstances, rather than trying to work around this (pretty broken) behavior that's also a pretty rare
      # edge case for us.
      return if defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby' && @dh.database_type == :mysql

      my_user = ::User.new
      my_user.name = 'User 1'
      my_user.save!

      user_bd = ::UserBackdoor.find(my_user.id)
      user_bd.name.should == 'User 1'
      user_bd.text_attrs_nonnull.should == ""
      user_bd.text_attrs_null.should == nil
      user_bd.binary_attrs_nonnull.should == ""
      user_bd.binary_attrs_null.should == nil
    end

    it "should store NULL or the empty string in the database, as appropriate, if there's no data left any more" do
      my_user = ::User.new
      my_user.name = 'User 1'
      my_user.aaa = 'aaa1'
      my_user.bbb = 'bbb1'
      my_user.ccc = 'ccc1'
      my_user.ddd = 'ddd1'
      my_user.save!

      user_bd = ::UserBackdoor.find(my_user.id)
      user_bd.name.should == 'User 1'
      check_text_column_data(user_bd.text_attrs_nonnull, 'aaa', 'aaa1')
      check_text_column_data(user_bd.text_attrs_null, 'bbb', 'bbb1')
      check_binary_column_data(user_bd.binary_attrs_nonnull, 'ccc', 'ccc1')
      check_binary_column_data(user_bd.binary_attrs_null, 'ddd', 'ddd1')

      user_again = ::User.find(my_user.id)
      user_again.aaa = nil
      user_again.bbb = nil
      user_again.ccc = nil
      user_again.ddd = nil
      user_again.save!

      user_bd_again = ::UserBackdoor.find(my_user.id)
      user_bd_again.name.should == 'User 1'
      user_bd_again.text_attrs_nonnull.should == ""
      user_bd_again.text_attrs_null.should == nil
      user_bd_again.binary_attrs_nonnull.should == ""
      user_bd_again.binary_attrs_null.should == nil
    end
  end
end
