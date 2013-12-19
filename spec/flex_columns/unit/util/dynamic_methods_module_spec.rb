require 'flex_columns'

describe FlexColumns::Util::DynamicMethodsModule do
  before :each do
    @target_class = Class.new
    @target_class_name = "FCUDMMSpec_#{rand(1_000_000_000)}"
    ::Object.const_set(@target_class_name, @target_class)

    @target_class.name.should == @target_class_name
  end

  def klass
    FlexColumns::Util::DynamicMethodsModule
  end

  it "should validate its arguments to #initialize correctly" do
    lambda { klass.new(@target_class, :foo) }.should raise_error(NameError)
    lambda { klass.new(Module.new, :Foo) }.should raise_error(ArgumentError)
    lambda { klass.new(@target_class, 123) }.should raise_error(ArgumentError)
  end

  it "should blow up if something else is already bound to the target class" do
    @target_class.const_set(:SpecDmm, :binding_conflict)
    lambda { klass.new(@target_class, :SpecDmm) }.should raise_error(NameError, /specdmm/i)
  end

  it "should run any code passed as a block into the constructor" do
    instance = klass.new(@target_class, :SpecDmm) do
      def bar
        "bar!!"
      end
    end

    target_instance = @target_class.new
    target_instance.bar.should == "bar!!"
  end

  context "with a valid instance" do
    before :each do
      @instance = klass.new(@target_class, :SpecDmm)
    end

    it "should bind itself to the correct constant name in the target class" do
      @target_class.const_get(:SpecDmm).should be(@instance)
    end

    it "should end up named correctly" do
      @instance.name.should == "#{@target_class_name}::SpecDmm"
    end

    it "should include itself in the target class" do
      @target_class.included_modules.include?(@instance).should be
    end

    it "should define new methods, and remove them all with #remove_all_methods!" do
      target_instance = @target_class.new
      target_instance.respond_to?(:foo).should_not be
      target_instance.respond_to?(:bar).should_not be
      lambda { target_instance.foo }.should raise_error(NoMethodError)
      lambda { target_instance.bar }.should raise_error(NoMethodError)

      @instance.define_method(:foo) { |*args, &block| args.join("FOO") + (block.try(:call) || '') }
      @instance.define_method(:bar) { |*args, &block| args.join("BAR") + (block.try(:call) || '') }

      target_instance.respond_to?(:foo).should be
      target_instance.respond_to?(:bar).should be

      (target_instance.foo(1, 2, 3) { "XX" }).should == "1FOO2FOO3XX"
      (target_instance.bar(3, 4, 5) { "YY" }).should == "3BAR4BAR5YY"

      @instance.remove_all_methods!
      target_instance.respond_to?(:foo).should_not be
      target_instance.respond_to?(:bar).should_not be
      lambda { target_instance.foo }.should raise_error(NoMethodError)
      lambda { target_instance.bar }.should raise_error(NoMethodError)

      @instance.define_method(:foo) { |*args, &block| (block.try(:call) || '') + args.join("f") }
      @instance.define_method(:bar) { |*args, &block| (block.try(:call) || '') + args.join("b") }

      target_instance.respond_to?(:foo).should be
      target_instance.respond_to?(:bar).should be

      (target_instance.foo(1, 2, 3) { "aa" }).should == "aa1f2f3"
      (target_instance.bar(3, 4, 5) { "zz" }).should == "zz3b4b5"
    end

    it "should let you make methods private, without using #send" do
      target_instance = @target_class.new
      target_instance.respond_to?(:foo).should_not be
      target_instance.respond_to?(:bar).should_not be
      lambda { target_instance.foo }.should raise_error(NoMethodError)
      lambda { target_instance.bar }.should raise_error(NoMethodError)

      @instance.define_method(:foo) { "foo!" }
      @instance.define_method(:bar) { "bar!" }
      @instance.private(:bar)

      target_instance.respond_to?(:foo).should be
      target_instance.respond_to?(:bar).should_not be
      target_instance.foo.should == "foo!"
      lambda { target_instance.bar }.should raise_error(NoMethodError)
      target_instance.send(:bar).should == "bar!"
    end
  end
end
