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
      create_table_error = nil

      migrate do
        drop_table :flexcols_spec_users rescue nil

        begin
          create_table :flexcols_spec_users do |t|
            t.string :name, :null => false
            t.column :user_attributes, :json
          end
        rescue ActiveRecord::StatementInvalid => si
          create_table_error = si
        end
      end

      @create_table_error = create_table_error
    end

    after :each do
      migrate do
        # drop_table :flexcols_spec_users rescue nil
      end
    end

    it "should store JSON, without a binary header or compression, in a column typed of JSON" do
      if @create_table_error
        $stderr.puts "Skipping PostgreSQL test of JSON type, because PostgreSQL didn't seem to create our table successfully -- likely because its version is < 9.2, and thus has no support for the JSON type: #{@create_table_error.message} (#{@create_table_error.class.name})"
      else
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

        user_again = ::User.find(user.id)
        user_again.name.should == 'User 1'
        user_again.wants_email.should == 'foo' * 10_000

        user_bd = ::UserBackdoor.find(user.id)
        raw = user_bd.user_attributes

        parsed = nil
        if raw.kind_of?(String)
          string.length.should > 30_000
          string.should match(/^\s*\{/i)
          parsed = JSON.parse(string)
        elsif raw.kind_of?(Hash)
          parsed = raw
        else
          raise "Unknown raw: #{raw.inspect}"
        end

        parsed['wants_email'].should == "foo" * 10_000
        parsed.keys.should == [ 'wants_email' ]

        if raw.kind_of?(Hash)
          as_stored = user.user_attributes.to_stored_data
          as_stored.class.should == Hash
        end
      end
    end
  end
end
