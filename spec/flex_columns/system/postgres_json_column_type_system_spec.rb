require 'flex_columns'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns PostgreSQL JSON column type support" do
  include FlexColumns::Helpers::SystemHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!
  end

  dbtype = FlexColumns::Helpers::DatabaseHelper.new.database_type

  if dbtype == :postgres
    before :each do
      migrate do
        drop_table :flexcols_spec_users rescue nil
        create_table :flexcols_spec_users do |t|
          t.string :name, :null => false
          t.column :user_attributes, :json
        end
      end
    end

    after :each do
      migrate do
        # drop_table :flexcols_spec_users rescue nil
      end
    end

    it "should store JSON, without a binary header or compression, in a column typed of JSON" do
      define_model_class(:User, 'flexcols_spec_users') do
        flex_column :user_attributes do
          field :wants_email
        end
      end

      define_model_class(:UserBackdoor, 'flexcols_spec_users') { }

      user = ::User.new
      user.name = 'User 1'
      user.wants_email = 'foo' * 10_000
      user.save!

      user_bd = ::UserBackdoor.find(user.id)
      string = user_bd.user_attributes
      string.length.should > 30_000
      string.should match(/^\s*\{/i)
      parsed = JSON.parse(string)
      parsed['wants_email'].should == "foo" * 10_000
      parsed.keys.should == [ 'wants_email' ]
    end
  end
end
