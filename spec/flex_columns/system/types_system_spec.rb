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

  def should_fail_validation(field, value, pattern = nil)
    object = ::User.new
    object.some_integer = 123

    object.send("#{field}=", value)

    object.valid?.should_not be

    full_name = "user_attributes.#{field}".to_sym
    object.errors.keys.should == [ full_name ]

    if pattern
      object.errors[full_name].length.should == 1
      object.errors[full_name][0].should match(pattern)
    end
  end

  it "should allow 'types' as shorthand for validations" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :some_integer, :integer, :null => false
        field :some_string, :string, :limit => 100
        field :some_string_2, :text
        field :some_float, :float
        field :some_float_2, :decimal
        field :some_date, :date
        field :some_time, :time
        field :some_datetime, :datetime
        field :some_timestamp, :timestamp
        field :some_boolean, :boolean
        field :some_enum, :enum => [ 'foo', 'bar', 'baz', nil ]
      end
    end

    should_fail_validation(:some_integer, "foo", /is not a number/i)
    should_fail_validation(:some_string, 12345, /must be a String/i)
    should_fail_validation(:some_string_2, 12345, /must be a String/i)
    should_fail_validation(:some_string, "foobar" * 100, /is too long/i)
    should_fail_validation(:some_float, "foo", /is not a number/i)
    should_fail_validation(:some_float_2, "foo", /is not a number/i)
    should_fail_validation(:some_time, "foo", /must be a Time/i)
    should_fail_validation(:some_datetime, "foo", /must be a Time/i)
    should_fail_validation(:some_timestamp, "foo", /must be a Time/i)
    should_fail_validation(:some_boolean, "true", /is not included in the list/i)
    should_fail_validation(:some_enum, "quux", /is not included in the list/i)

    user = ::User.new
    user.name = 'User 1'

    user.user_attributes.some_integer = 12345
    user.user_attributes.some_string = "foo"
    user.user_attributes.some_string_2 = "bar"
    user.user_attributes.some_float = 5.2
    user.user_attributes.some_float_2 = 10.7
    user.user_attributes.some_date = Date.today
    user.user_attributes.some_time = Time.now
    user.user_attributes.some_datetime = 1.day.from_now
    user.user_attributes.some_timestamp = 1.minute.from_now
    user.user_attributes.some_boolean = true
    user.user_attributes.some_enum = 'foo'

    user.valid?.should be

    user.user_attributes.some_string = ''
    user.valid?.should be

    user.user_attributes.some_float = 15
    user.valid?.should be

    user.user_attributes.some_boolean = nil
    user.valid?.should be

    user.user_attributes.some_string = :bonk
    user.valid?.should be
  end
end
