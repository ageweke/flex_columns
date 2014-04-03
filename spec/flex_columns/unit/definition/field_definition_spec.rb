require 'flex_columns'
require 'flex_columns/helpers/exception_helpers'

describe FlexColumns::Definition::FieldDefinition do
  include FlexColumns::Helpers::ExceptionHelpers

  def klass
    FlexColumns::Definition::FieldDefinition
  end

  it "should normalize names properly" do
    lambda { klass.normalize_name(nil) }.should raise_error(ArgumentError)
    lambda { klass.normalize_name(123) }.should raise_error(ArgumentError)
    klass.normalize_name("  FoO ").should == :foo
    klass.normalize_name(:foo).should == :foo
  end

  before :each do
    @flex_column_class = double("flex_column_class")
    allow(@flex_column_class).to receive(:is_flex_column_class?).with().and_return(true)
  end

  describe "#initialize" do
    it "should validate its arguments" do
      non_fcc = double("flex_column_class")
      lambda { klass.new(non_fcc, :foo, [ ], { }) }.should raise_error(ArgumentError)

      non_fcc = double("flex_column_class")
      allow(non_fcc).to receive(:is_flex_column_class?).with().and_return(false)
      lambda { klass.new(non_fcc, :foo, [ ], { }) }.should raise_error(ArgumentError)

      lambda { klass.new(@flex_column_class, :foo, [ ], { :foo => :bar }) }.should raise_error(ArgumentError)

      lambda { klass.new(@flex_column_class, :foo, [ ], { :visibility => 123 }) }.should raise_error(ArgumentError)
      lambda { klass.new(@flex_column_class, :foo, [ ], { :visibility => true }) }.should raise_error(ArgumentError)

      lambda { klass.new(@flex_column_class, :foo, [ ], { :json => 123 }) }.should raise_error(ArgumentError)

      lambda { klass.new(@flex_column_class, :foo, [ ], { :null => 123 }) }.should raise_error(ArgumentError)
    end

    it "should raise an error if there are additional arguments" do
      expect(@flex_column_class).to receive(:validates).once.with(:foo, { :numericality => { :only_integer => true }, :allow_nil => true})
      lambda { klass.new(@flex_column_class, :foo, [ :integer, :bar ], { }) }.should raise_error(ArgumentError)
    end

    describe "types support" do
      it "should raise an error if given an invalid type" do
        lambda { klass.new(@flex_column_class, :foo, [ :bar ], { }) }.should raise_error(ArgumentError)
      end

      it "should force a value to be present if :null => false" do
        expect(@flex_column_class).to receive(:validates).once.with(:foo, { :presence => true })
        klass.new(@flex_column_class, :foo, [ ], { :null => false })
      end

      it "should force a value to be in an :enum list" do
        expect(@flex_column_class).to receive(:validates).once.with(:foo, { :inclusion => { :in => %w{a b c} } })
        klass.new(@flex_column_class, :foo, [ ], { :enum => %w{a b c} })
      end

      it "should force a value to be of a maximum length" do
        expect(@flex_column_class).to receive(:validates).once.with(:foo, { :length => { :maximum => 123 } })
        klass.new(@flex_column_class, :foo, [ ], { :limit => 123 })
      end

      def expect_validation(type, arguments)
        expect(@flex_column_class).to receive(:validates).once.with(:foo, arguments)
        klass.new(@flex_column_class, :foo, [ type ], { })
      end

      it "should validate integers properly" do
        expect_validation(:integer, { :numericality => { :only_integer => true }, :allow_nil => true })
      end

      it "should validate floats properly" do
        expect_validation(:float, { :numericality => true, :allow_nil => true })
      end

      it "should validate decimals properly" do
        expect_validation(:decimal, { :numericality => true, :allow_nil => true })
      end

      it "should validate booleans properly" do
        expect_validation(:boolean, { :inclusion => { :in => [ true, false, nil ] }})
      end

      def check_validation_block(type, input, expected_error)
        validation_block = nil
        expect(@flex_column_class).to receive(:validates_each).once.with(:foo) do |&block|
          validation_block = block
        end

        klass.new(@flex_column_class, :foo, [ type.to_sym ], { })

        record = double("record")
        errors = double("errors")

        allow(record).to receive(:errors).with().and_return(errors)

        if expected_error
          expect(errors).to receive(:add).once.with(:foo, expected_error)
        end

        validation_block.call(record, :foo, input)
      end

      %w{string text}.each do |type|
        it "should validate fields of type #{type} properly" do
          check_validation_block(type, "aaa", nil)
          check_validation_block(type, :aaa, nil)
          check_validation_block(type, nil, nil)
          check_validation_block(type, 123, "must be a String")
        end
      end

      it "should validate dates correctly" do
        check_validation_block(:date, nil, nil)
        check_validation_block(:date, Date.today, nil)
        check_validation_block(:date, Time.now, "must be a Date")
        check_validation_block(:date, DateTime.now, nil)
        check_validation_block(:date, 123, "must be a Date")
      end

      it "should validate times correctly" do
        check_validation_block(:time, nil, nil)
        check_validation_block(:time, Date.today, "must be a Time")
        check_validation_block(:time, Time.now, nil)
        check_validation_block(:time, DateTime.now, "must be a Time")
        check_validation_block(:time, 123, "must be a Time")
      end

      %w{timestamp datetime}.each do |type|
        it "should validate fields of type #{type} properly" do
          check_validation_block(type, nil, nil)
          check_validation_block(type, Time.now, nil)

          check_validation_block(type, DateTime.now, nil)

          check_validation_block(type, 123, "must be a Time or DateTime")
          check_validation_block(type, Date.today, "must be a Time or DateTime")
        end
      end
    end
  end

  it "should return the JSON storage name from #json_storage_name" do
    klass.new(@flex_column_class, :foo, [ ], { }).json_storage_name.should == :foo
    klass.new(@flex_column_class, :foo, [ ], { :json => :bar }).json_storage_name.should == :bar
  end

  describe "#add_methods_to_flex_column_class!" do
    before :each do
      @dmm = Class.new do
        class << self; public :define_method, :private; end

        def initialize(h)
          @h = h
        end

        def [](x)
          @h[x]
        end

        def []=(x, y)
          @h[x] = y
        end
      end
    end

    it "should define methods on the flex-column class" do
      allow(@flex_column_class).to receive(:fields_are_private_by_default?).with().and_return(false)
      klass.new(@flex_column_class, :foo, [ ], { :json => :bar }).add_methods_to_flex_column_class!(@dmm)

      instance = @dmm.new(:foo => 123)
      instance.foo.should == 123
      instance.foo = 234
      instance.foo.should == 234
    end

    it "should define methods on the flex-column class privately if the flex-column says to" do
      allow(@flex_column_class).to receive(:fields_are_private_by_default?).with().and_return(true)
      klass.new(@flex_column_class, :foo, [ ], { :json => :bar }).add_methods_to_flex_column_class!(@dmm)

      instance = @dmm.new(:foo => 123)

      lambda { instance.foo }.should raise_error(NoMethodError)
      lambda { instance.foo = 123 }.should raise_error(NoMethodError)

      instance.send(:foo).should == 123
      instance.send(:foo=, 234)
      instance.send(:foo).should == 234
    end

    it "should define methods on the flex-column class privately if the field says to" do
      allow(@flex_column_class).to receive(:fields_are_private_by_default?).with().and_return(false)
      klass.new(@flex_column_class, :foo, [ ], { :json => :bar, :visibility => :private }).add_methods_to_flex_column_class!(@dmm)

      instance = @dmm.new(:foo => 123)

      lambda { instance.foo }.should raise_error(NoMethodError)
      lambda { instance.foo = 123 }.should raise_error(NoMethodError)

      instance.send(:foo).should == 123
      instance.send(:foo=, 234)
      instance.send(:foo).should == 234
    end

    it "should define methods on the flex-column class publicly if the field says to" do
      allow(@flex_column_class).to receive(:fields_are_private_by_default?).with().and_return(true)
      klass.new(@flex_column_class, :foo, [ ], { :json => :bar, :visibility => :public }).add_methods_to_flex_column_class!(@dmm)

      instance = @dmm.new(:foo => 123)
      instance.foo.should == 123
      instance.foo = 234
      instance.foo.should == 234
    end
  end

  describe "#add_methods_to_model_class!" do
    before :each do
      @dmm = Class.new do
        class << self; public :define_method, :private; end
      end

      @model_class = double("model_class")
    end

    def check_add_methods_to_model_class(options)
      create_options = options[:create_options]
      fields_are_private_by_default = options[:fields_are_private_by_default] || false
      safe_to_define = if options.has_key?(:safe_to_define) then options[:safe_to_define] else true end
      delegation_type = options[:delegation_type]
      delegation_prefix = options[:delegation_prefix]
      method_name = options[:method_name]
      should_be_private = options[:should_be_private]
      method_should_exist = if options.has_key?(:method_should_exist) then options[:method_should_exist] else true end

      flex_instance = { }
      field = klass.new(@flex_column_class, :foo, [ ], create_options)
      allow(@flex_column_class).to receive(:fields_are_private_by_default?).with().and_return(fields_are_private_by_default)

      allow(@model_class).to receive(:_flex_columns_safe_to_define_method?).with(method_name.to_sym).and_return(safe_to_define)
      allow(@model_class).to receive(:_flex_columns_safe_to_define_method?).with("#{method_name}=".to_sym).and_return(safe_to_define)
      allow(@flex_column_class).to receive(:delegation_type).with().and_return(delegation_type)
      allow(@flex_column_class).to receive(:delegation_prefix).with().and_return(delegation_prefix)

      field.add_methods_to_model_class!(@dmm, @model_class)

      instance = @dmm.new
      allow(@flex_column_class).to receive(:object_for).with(instance).and_return(flex_instance)

      if (! method_should_exist)
        lambda { instance.send(method_name) }.should raise_error(NoMethodError)
        lambda { instance.send("#{method_name}=", 123) }.should raise_error(NoMethodError)
      elsif should_be_private
        lambda { eval("instance.#{method_name}") }.should raise_error(NoMethodError)
        lambda { eval("instance.#{method_name} = 123") }.should raise_error(NoMethodError)
        instance.send(method_name).should be_nil
        instance.send("#{method_name}=", 123).should == 123
        instance.send(method_name).should == 123
      else
        eval("instance.#{method_name}").should be_nil
        eval("instance.#{method_name} = 123").should == 123
        eval("instance.#{method_name}").should == 123
      end
    end

    it "should define a very standard public method just fine" do
      check_add_methods_to_model_class(
        :create_options => { },
        :fields_are_private_by_default => false,
        :safe_to_define => true,
        :delegation_type => :public,
        :delegation_prefix => nil,
        :method_name => :foo,
        :should_be_private => false
      )
    end

    it "should define a private method if asked to on the field" do
      check_add_methods_to_model_class(
        :create_options => { :visibility => :private },
        :fields_are_private_by_default => false,
        :safe_to_define => true,
        :delegation_type => :public,
        :delegation_prefix => nil,
        :method_name => :foo,
        :should_be_private => true
      )
    end

    it "should define a private method if fields are private by default" do
      check_add_methods_to_model_class(
        :create_options => { },
        :fields_are_private_by_default => true,
        :safe_to_define => true,
        :delegation_type => :public,
        :delegation_prefix => nil,
        :method_name => :foo,
        :should_be_private => true
      )
    end

    it "should define a private method if fields are private by default, but the specific field is public" do
      check_add_methods_to_model_class(
        :create_options => { :visibility => :public },
        :fields_are_private_by_default => true,
        :safe_to_define => true,
        :delegation_type => :public,
        :delegation_prefix => nil,
        :method_name => :foo,
        :should_be_private => false
      )
    end

    it "should define a private method if delegation is private" do
      check_add_methods_to_model_class(
        :create_options => { },
        :fields_are_private_by_default => false,
        :safe_to_define => true,
        :delegation_type => :private,
        :delegation_prefix => nil,
        :method_name => :foo,
        :should_be_private => true
      )
    end

    it "should not define a method if delegation is off" do
      check_add_methods_to_model_class(
        :create_options => { },
        :fields_are_private_by_default => false,
        :safe_to_define => true,
        :delegation_type => nil,
        :delegation_prefix => nil,
        :method_name => :foo,
        :should_be_private => false,
        :method_should_exist => false
      )
    end

    it "should not define a method if it's not safe to do so" do
      check_add_methods_to_model_class(
        :create_options => { },
        :fields_are_private_by_default => false,
        :safe_to_define => false,
        :delegation_type => :public,
        :delegation_prefix => nil,
        :method_name => :foo,
        :should_be_private => false,
        :method_should_exist => false
      )
    end

    it "should prefix the method if requested" do
      check_add_methods_to_model_class(
        :create_options => { },
        :fields_are_private_by_default => false,
        :safe_to_define => true,
        :delegation_type => :public,
        :delegation_prefix => :aaa,
        :method_name => :aaa_foo,
        :should_be_private => false,
        :method_should_exist => true
      )
    end
  end

  describe "#add_methods_to_included_class!" do
    def check_add_methods_to_included_class(options)
      delegation_type = options[:delegation_type]
      delegation_prefix = options[:delegation_prefix]
      create_options = options[:create_options]
      fields_are_private_by_default = options[:fields_are_private_by_default] || false
      method_name = options[:method_name]
      safe_to_define = options[:safe_to_define]
      include_options = options[:include_options]
      method_should_exist = options[:method_should_exist]
      should_be_private = options[:should_be_private]

      allow(@flex_column_class).to receive(:delegation_type).with().and_return(delegation_type)
      allow(@flex_column_class).to receive(:delegation_prefix).with().and_return(delegation_prefix)
      allow(@flex_column_class).to receive(:fields_are_private_by_default?).with().and_return(fields_are_private_by_default)

      @model_class = double("model_class")
      allow(@model_class).to receive(:name).with().and_return("mcname")
      allow(@flex_column_class).to receive(:model_class).with().and_return(@model_class)
      allow(@flex_column_class).to receive(:column_name).with().and_return(:colname)

      target_class = double("target_class")
      allow(target_class).to receive(:_flex_columns_safe_to_define_method?).with(method_name.to_sym).and_return(safe_to_define)
      allow(target_class).to receive(:_flex_columns_safe_to_define_method?).with("#{method_name}=".to_sym).and_return(safe_to_define)

      associated_object = double("associated_object")

      @dmm = Class.new do
        def ao=(x)
          @associated_object = x
        end

        def ao
          @associated_object
        end

        def bao=(x)
          @build_associated_object = x
        end

        def build_ao
          @build_associated_object
        end

        class << self; public :define_method, :private; end
      end

      field = klass.new(@flex_column_class, :foo, [ ], create_options)
      field.add_methods_to_included_class!(@dmm, :ao, target_class, include_options)

      instance = @dmm.new

      if options[:use_build]
        instance.bao = associated_object
      else
        instance.ao = associated_object
      end

      flex_instance = Object.new
      class << flex_instance
        def foo=(x)
          @foo = x
        end

        def foo
          @foo
        end
      end

      allow(associated_object).to receive(:colname).and_return(flex_instance)

      if (! method_should_exist)
        lambda { instance.send(method_name) }.should raise_error(NoMethodError)
        lambda { instance.send("#{method_name}=", 123) }.should raise_error(NoMethodError)
      elsif should_be_private
        lambda { eval("instance.#{method_name}") }.should raise_error(NoMethodError)
        lambda { eval("instance.#{method_name} = 123") }.should raise_error(NoMethodError)
        instance.send(method_name).should be_nil
        instance.send("#{method_name}=", 123).should == 123
        instance.send(method_name).should == 123
      else
        eval("instance.#{method_name}").should be_nil
        eval("instance.#{method_name} = 123").should == 123
        eval("instance.#{method_name}").should == 123
      end
    end

    it "should define a very standard public method just fine" do
      check_add_methods_to_included_class(
        :delegation_type => :public,
        :delegation_prefix => nil,
        :create_options => { },
        :fields_are_private_by_default => false,
        :method_name => :foo,
        :safe_to_define => true,
        :include_options => { },
        :method_should_exist => true,
        :should_be_private => false
      )
    end

    it "should define a private method if the field is private" do
      check_add_methods_to_included_class(
        :delegation_type => :public,
        :delegation_prefix => nil,
        :create_options => { :visibility => :private },
        :fields_are_private_by_default => false,
        :method_name => :foo,
        :safe_to_define => true,
        :include_options => { },
        :method_should_exist => true,
        :should_be_private => true
      )
    end

    it "should define a private method if the flex column is private" do
      check_add_methods_to_included_class(
        :delegation_type => :public,
        :delegation_prefix => nil,
        :create_options => { },
        :fields_are_private_by_default => true,
        :method_name => :foo,
        :safe_to_define => true,
        :include_options => { },
        :method_should_exist => true,
        :should_be_private => true
      )
    end

    it "should define a public method if the flex column is private but the field is public" do
      check_add_methods_to_included_class(
        :delegation_type => :public,
        :delegation_prefix => nil,
        :create_options => { :visibility => :public },
        :fields_are_private_by_default => true,
        :method_name => :foo,
        :safe_to_define => true,
        :include_options => { },
        :method_should_exist => true,
        :should_be_private => false
      )
    end

    it "should default to the flex-column prefix" do
      check_add_methods_to_included_class(
        :delegation_type => :public,
        :delegation_prefix => :aaa,
        :create_options => { },
        :fields_are_private_by_default => false,
        :method_name => :aaa_foo,
        :safe_to_define => true,
        :include_options => { },
        :method_should_exist => true,
        :should_be_private => false
      )
    end

    it "should override to the flex-column prefix if requested" do
      check_add_methods_to_included_class(
        :delegation_type => :public,
        :delegation_prefix => :aaa,
        :create_options => { },
        :fields_are_private_by_default => false,
        :method_name => :bbb_foo,
        :safe_to_define => true,
        :include_options => { :prefix => :bbb },
        :method_should_exist => true,
        :should_be_private => false
      )
    end

    it "should override to the flex-column prefix with no prefix if requested" do
      check_add_methods_to_included_class(
        :delegation_type => :public,
        :delegation_prefix => :aaa,
        :create_options => { },
        :fields_are_private_by_default => false,
        :method_name => :foo,
        :safe_to_define => true,
        :include_options => { :prefix => nil },
        :method_should_exist => true,
        :should_be_private => false
      )
    end

    it "should raise if you ask for public methods from a private field" do
      e = capture_exception(ArgumentError) do
        check_add_methods_to_included_class(
          :delegation_type => :public,
          :delegation_prefix => nil,
          :create_options => { },
          :fields_are_private_by_default => true,
          :method_name => :foo,
          :safe_to_define => true,
          :include_options => { :visibility => :public },
          :method_should_exist => true,
          :should_be_private => true
        )
      end

      e.message.should match(/ao/i)
      e.message.should match(/mcname/i)
      e.message.should match(/colname/i)
    end

    it "should skip defining methods if there's no delegation" do
      check_add_methods_to_included_class(
        :delegation_type => nil,
        :delegation_prefix => nil,
        :create_options => { },
        :fields_are_private_by_default => false,
        :method_name => :foo,
        :safe_to_define => true,
        :include_options => { },
        :method_should_exist => false,
        :should_be_private => false
      )
    end

    it "should skip defining methods if it's not safe" do
      check_add_methods_to_included_class(
        :delegation_type => :public,
        :delegation_prefix => nil,
        :create_options => { },
        :fields_are_private_by_default => false,
        :method_name => :foo,
        :safe_to_define => false,
        :include_options => { },
        :method_should_exist => false,
        :should_be_private => false
      )
    end

    it "should build the association if needed" do
      check_add_methods_to_included_class(
        :delegation_type => :public,
        :delegation_prefix => nil,
        :create_options => { },
        :fields_are_private_by_default => false,
        :method_name => :foo,
        :safe_to_define => true,
        :include_options => { },
        :method_should_exist => true,
        :should_be_private => false,
        :use_build => true
      )
    end
  end
end
