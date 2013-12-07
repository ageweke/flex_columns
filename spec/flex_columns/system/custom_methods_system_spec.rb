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

  it "should allow defining methods that are present on both the attributes class and the enclosing class" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes do
        field :number_of_emails_sent

        def increment_number_of_emails_sent
          self.number_of_emails_sent += 1
        end

        def change_number_of_emails_sent(return_value)
          self.number_of_emails_sent = yield number_of_emails_sent
          return_value
        end
      end
    end

    user = ::User.new
    user.name = 'User 1'

    user.user_attributes.number_of_emails_sent = 15
    user.user_attributes.increment_number_of_emails_sent
    user.user_attributes.number_of_emails_sent.should == 16
    (user.user_attributes.change_number_of_emails_sent('abc') { |x| x - 5 }).should == 'abc'
    user.user_attributes.number_of_emails_sent.should == 11

    user.number_of_emails_sent.should == 11
    user.increment_number_of_emails_sent
    user.number_of_emails_sent.should == 12
    (user.change_number_of_emails_sent('abc') { |x| x - 5 }).should == 'abc'
    user.number_of_emails_sent.should == 7
  end

  it "should not delegate methods if told not to" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :delegate => false do
        field :number_of_emails_sent

        def increment_number_of_emails_sent
          self.number_of_emails_sent += 1
        end

        def change_number_of_emails_sent(return_value)
          self.number_of_emails_sent = yield number_of_emails_sent
          return_value
        end
      end
    end

    user = ::User.new
    user.name = 'User 1'

    user.respond_to?(:number_of_emails_sent).should_not be
    user.respond_to?(:increment_number_of_emails_sent).should_not be
    user.respond_to?(:change_number_of_emails_sent).should_not be
  end

  it "should delegate methods privately if told to" do
    define_model_class(:User, 'flexcols_spec_users') do
      flex_column :user_attributes, :delegate => :private do
        field :number_of_emails_sent

        def increment_number_of_emails_sent
          self.number_of_emails_sent += 1
        end

        def change_number_of_emails_sent(return_value)
          self.number_of_emails_sent = yield number_of_emails_sent
          return_value
        end
      end

      def nes=(x)
        self.number_of_emails_sent = x
      end

      def nes
        number_of_emails_sent
      end

      def ies
        increment_number_of_emails_sent
      end

      def cnes(rv, &block)
        change_number_of_emails_sent(rv, &block)
      end
    end

    user = ::User.new
    user.name = 'User 1'

    user.respond_to?(:number_of_emails_sent).should_not be
    user.respond_to?(:increment_number_of_emails_sent).should_not be
    user.respond_to?(:change_number_of_emails_sent).should_not be

    user.nes = 10
    user.nes.should == 10
    user.ies
    user.nes.should == 11
    (user.cnes('abc') { |x| x - 5 }).should == 'abc'
    user.nes.should == 6
  end
end
