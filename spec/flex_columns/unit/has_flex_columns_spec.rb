require 'flex_columns'
require 'flex_columns/helpers/exception_helpers'

describe FlexColumns::HasFlexColumns do
  include FlexColumns::Helpers::ExceptionHelpers

  before :each do
    @klass = Class.new do
      class << self
        def before_validation(*args)
          @_before_validation_calls ||= [ ]
          @_before_validation_calls << args
        end

        def before_save(*args)
          @_before_save_calls ||= [ ]
          @_before_save_calls << args
        end

        def before_validation_calls
          @_before_validation_calls
        end

        def before_save_calls
          @_before_save_calls
        end
      end
    end

    @klass_name = "HasFlexColumnsSpec_#{rand(1_000_000_000)}"
    ::Object.const_set(@klass_name, @klass)

    @klass.send(:include, FlexColumns::HasFlexColumns)
  end

  it "should call before_validation and before_save to set up hooks properly" do
    @klass.before_validation_calls.length.should == 1
    @klass.before_validation_calls[0].should == [ :_flex_columns_before_validation! ]
    @klass.before_save_calls.length.should == 1
    @klass.before_save_calls[0].should == [ :_flex_columns_before_save! ]
  end

  it "should normalize names properly" do
    @klass._flex_column_normalize_name(" FoO ").should == :foo
    @klass._flex_column_normalize_name(:fOo).should == :foo
  end

  context "with two declared flex columns" do
    before :each do
      @fcc_foo = double("fcc_foo")
      expect(Class).to receive(:new).once.with(FlexColumns::Contents::FlexColumnContentsBase).and_return(@fcc_foo)
      expect(@fcc_foo).to receive(:setup!).once.with(@klass, :foo, { :aaa => :bbb, :ccc => :ddd })
      expect(@fcc_foo).to receive(:sync_methods!).once

      allow(@fcc_foo).to receive(:column_name).with().and_return(:foo)

      @dmm = double("dmm")
      expect(FlexColumns::Util::DynamicMethodsModule).to receive(:new).once.with(@klass, :FlexColumnsDynamicMethods).and_return(@dmm)
      expect(@dmm).to receive(:remove_all_methods!).once.with()

      @klass.flex_column(:foo, :aaa => :bbb, :ccc => :ddd)

      @fcc_bar = double("fcc_bar")
      expect(Class).to receive(:new).once.with(FlexColumns::Contents::FlexColumnContentsBase).and_return(@fcc_bar)
      expect(@fcc_bar).to receive(:setup!).once.with(@klass, :bar, { })
      expect(@fcc_bar).to receive(:sync_methods!).once

      allow(@fcc_bar).to receive(:column_name).with().and_return(:bar)

      expect(@dmm).to receive(:remove_all_methods!).once.with()
      expect(@fcc_foo).to receive(:sync_methods!).once
      @klass.flex_column(:bar)
    end

    it "should return the same DynamicMethodsModule every time" do
      @klass._flex_column_dynamic_methods_module.should be(@dmm)
      @klass._flex_column_dynamic_methods_module.should be(@dmm)
    end

    it "should return the flex-column class from #_flex_column_class_for" do
      @klass._flex_column_class_for(:foo).should be(@fcc_foo)
      @klass._flex_column_class_for(:bar).should be(@fcc_bar)
      @klass._flex_column_class_for(:foo).should be(@fcc_foo)

      e = capture_exception(FlexColumns::Errors::NoSuchColumnError) { @klass._flex_column_class_for(:baz) }
      e.message.should match(/baz/)
      e.message.should match(/foo/)
      e.message.should match(/bar/)
      e.message.should match(@klass_name)
    end

    it "should create a method that returns a new instance, but only once" do
      instance = @klass.new
      fcc_foo_instance = double("fcc_foo_instance")
      expect(@fcc_foo).to receive(:new).once.with(instance).and_return(fcc_foo_instance)
      instance.foo.should be(fcc_foo_instance)
      instance.foo.should be(fcc_foo_instance)
    end

    it "should overwrite previous columns with new ones" do
      fcc_conflicting = double("fcc_conflicting")
      expect(Class).to receive(:new).once.with(FlexColumns::Contents::FlexColumnContentsBase).and_return(fcc_conflicting)
      expect(fcc_conflicting).to receive(:setup!).once.with(@klass, :foo, { })
      expect(fcc_conflicting).to receive(:sync_methods!).once
      allow(fcc_conflicting).to receive(:column_name).with().and_return(:foo)

      expect(@dmm).to receive(:remove_all_methods!).once.with()

      expect(@fcc_bar).to receive(:sync_methods!).once
      @klass.flex_column(:foo)

      instance = @klass.new
      fcc_instance = double("fcc_instance")
      expect(fcc_conflicting).to receive(:new).once.with(instance).and_return(fcc_instance)
      instance.foo.should be(fcc_instance)
      instance.foo.should be(fcc_instance)
    end
  end

  describe "flex-column objects" do
    it "should prefer to just return super from _flex_column_object_for" do
      superclass = Class.new do
        def _flex_column_object_for(x)
          "A_#{x}_Z"
        end
      end

      subclass = Class.new(superclass)
      allow(subclass).to receive(:before_validation).with(:_flex_columns_before_validation!)
      allow(subclass).to receive(:before_save).with(:_flex_columns_before_save!)
      subclass.send(:include, FlexColumns::HasFlexColumns)

      instance = subclass.new
      instance._flex_column_object_for(:foo).should == "A_foo_Z"
    end

    it "should create, and hold on to, flex-column objects properly"
  end
end
