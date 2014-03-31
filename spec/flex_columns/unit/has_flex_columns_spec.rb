require 'flex_columns'
require 'flex_columns/helpers/exception_helpers'

describe FlexColumns::HasFlexColumns do
  include FlexColumns::Helpers::ExceptionHelpers

  before :each do
    @superclass = Class.new

    @klass = Class.new(@superclass) do
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

        def table_exists?
          true
        end
      end

      def _flex_column_object_for(column_name, create_if_needed = true)
        _flex_column_owned_object_for(column_name, create_if_needed)
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

  it "should say it has flex columns" do
    @klass.has_any_flex_columns?.should be
  end

  describe "#flex_column" do
    it "should do nothing if the table doesn't exist" do
      allow(@klass).to receive(:table_exists?).with().and_return(false)
      @klass.flex_column('foo')
    end

    it "should normalize the name of the column" do
      fcc = double("fcc")
      expect(Class).to receive(:new).once.with(FlexColumns::Contents::FlexColumnContentsBase).and_return(fcc)
      expect(fcc).to receive(:setup!).once.with(@klass, :foo, { })
      allow(fcc).to receive(:sync_methods!).with()

      @klass.flex_column(' fOo ')
    end

    it "should replace existing columns, call #remove_all_methods! and #sync_methods! appropriately, and define a method that returns the right object" do
      fcc_foo = double("fcc_foo")
      expect(Class).to receive(:new).once.with(FlexColumns::Contents::FlexColumnContentsBase).and_return(fcc_foo)
      expect(fcc_foo).to receive(:quux).once.with(:a, :z, :q)

      passed_block = nil
      expect(fcc_foo).to receive(:setup!).once.with(@klass, :foo, { }) do |*args, &block|
        passed_block = block
      end
      allow(fcc_foo).to receive(:column_name).with().and_return(:foo)

      dmm = double("dmm")
      expect(FlexColumns::Util::DynamicMethodsModule).to receive(:new).once.with(@klass, :FlexColumnsDynamicMethods).and_return(dmm)

      expect(dmm).to receive(:remove_all_methods!).once.with()
      expect(fcc_foo).to receive(:sync_methods!).once.with()
      @klass.flex_column(:foo) do
        quux(:a, :z, :q)
      end
      fcc_foo.instance_eval(&passed_block)

      @klass._flex_column_class_for(:foo).should be(fcc_foo)

      instance = @klass.new
      fcc_foo_instance = double("fcc_foo_instance")
      expect(fcc_foo).to receive(:new).once.with(instance).and_return(fcc_foo_instance)
      instance.foo.should be(fcc_foo_instance)



      fcc_bar = double("fcc_bar")
      expect(Class).to receive(:new).once.with(FlexColumns::Contents::FlexColumnContentsBase).and_return(fcc_bar)
      expect(fcc_bar).to receive(:setup!).once.with(@klass, :bar, { })
      allow(fcc_bar).to receive(:column_name).with().and_return(:bar)

      expect(dmm).to receive(:remove_all_methods!).once.with()
      expect(fcc_foo).to receive(:sync_methods!).once.with()
      expect(fcc_bar).to receive(:sync_methods!).once.with()
      @klass.flex_column(:bar)

      @klass._flex_column_class_for(:foo).should be(fcc_foo)
      @klass._flex_column_class_for(:bar).should be(fcc_bar)

      fcc_bar_instance = double("fcc_bar_instance")
      expect(fcc_bar).to receive(:new).once.with(instance).and_return(fcc_bar_instance)
      instance.foo.should be(fcc_foo_instance)
      instance.bar.should be(fcc_bar_instance)


      fcc_foo_2 = double("fcc_foo_2")
      expect(Class).to receive(:new).once.with(FlexColumns::Contents::FlexColumnContentsBase).and_return(fcc_foo_2)
      expect(fcc_foo_2).to receive(:setup!).once.with(@klass, :foo, { :a => :b, :c => :d })
      allow(fcc_foo_2).to receive(:column_name).with().and_return(:foo)

      expect(dmm).to receive(:remove_all_methods!).once.with()
      expect(fcc_foo_2).to receive(:sync_methods!).once.with()
      expect(fcc_bar).to receive(:sync_methods!).once.with()

      @klass.flex_column(:foo, :a => :b, :c => :d)

      @klass._flex_column_class_for(:foo).should be(fcc_foo_2)
      @klass._flex_column_class_for(:bar).should be(fcc_bar)

      instance = @klass.new
      fcc_foo_2_instance = double("fcc_foo_2_instance")
      expect(fcc_foo_2).to receive(:new).once.with(instance).and_return(fcc_foo_2_instance)
      instance.foo.should be(fcc_foo_2_instance)

      instance = @klass.new
      fcc_bar_instance = double("fcc_bar_instance")
      expect(fcc_bar).to receive(:new).once.with(instance).and_return(fcc_bar_instance)
      instance.bar.should be(fcc_bar_instance)
    end
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

    describe "#read_attribute_for_serialization" do
      it "should call through to the flex-column object for flex columns, and flex columns only" do
        @superclass.class_eval do
          def read_attribute_for_serialization(attribute_name)
            "rafs_#{attribute_name}_rafs"
          end
        end

        instance = @klass.new

        fcc_foo_instance = double("fcc_foo_instance")
        expect(@fcc_foo).to receive(:new).once.with(instance).and_return(fcc_foo_instance)
        hash_for_serialization = double("hash_for_serialization")
        expect(fcc_foo_instance).to receive(:to_hash_for_serialization).once.with().and_return(hash_for_serialization)

        instance.read_attribute_for_serialization('foo').should be(hash_for_serialization)
        instance.read_attribute_for_serialization('baz').should == "rafs_baz_rafs"
      end
    end

    describe "#as_json" do
      it "should call through to the flex-column object for flex columns, and flex columns only" do
        @superclass.class_eval do
          def as_json(options)
            @superclass_as_json_options ||= [ ]
            @superclass_as_json_options << options
            { :z => 123, :bbb => 456}
          end
        end
        instance = @klass.new

        fcc_foo_instance = double("fcc_foo_instance")
        expect(@fcc_foo).to receive(:new).once.with(instance).and_return(fcc_foo_instance)
        expect(fcc_foo_instance).to receive(:to_hash_for_serialization).once.with().and_return({ :aaa => 111, :bbb => 222 })

        fcc_bar_instance = double("fcc_bar_instance")
        expect(@fcc_bar).to receive(:new).once.with(instance).and_return(fcc_bar_instance)
        expect(fcc_bar_instance).to receive(:to_hash_for_serialization).once.with().and_return({ :aaa => 234, :ccc => 'xxx' })

        allow(instance).to receive(:include_root_in_json).with().and_return(false)

        instance.as_json.should == { :z => 123, :bbb => 456,
          :foo => { :aaa => 111, :bbb => 222 },
          :bar => { :aaa => 234, :ccc => 'xxx' }
        }
        instance.instance_variable_get("@superclass_as_json_options").should == [
          { :except => [ :foo, :bar ] }
        ]
      end
    end

    it "should return the same DynamicMethodsModule every time" do
      @klass._flex_column_dynamic_methods_module.should be(@dmm)
      @klass._flex_column_dynamic_methods_module.should be(@dmm)
    end

    it "should call through on before_validation to all flex column objects, whether or not they've been deserialized" do
      instance = @klass.new
      instance._flex_columns_before_validation!

      fcc_foo_instance = double("fcc_foo_instance")
      expect(@fcc_foo).to receive(:new).once.with(instance).and_return(fcc_foo_instance)
      instance._flex_column_owned_object_for(:foo).should be(fcc_foo_instance)
      allow(fcc_foo_instance).to receive(:deserialized?).with().and_return(false)

      expect(fcc_foo_instance).to receive(:before_validation!).once.with()
      instance._flex_columns_before_validation!


      fcc_bar_instance = double("fcc_bar_instance")
      expect(@fcc_bar).to receive(:new).once.with(instance).and_return(fcc_bar_instance)
      instance._flex_column_owned_object_for(:bar).should be(fcc_bar_instance)
      allow(fcc_bar_instance).to receive(:deserialized?).with().and_return(true)

      expect(fcc_foo_instance).to receive(:before_validation!).once.with()
      expect(fcc_bar_instance).to receive(:before_validation!).once.with()
      instance._flex_columns_before_validation!

      allow(fcc_foo_instance).to receive(:deserialized?).with().and_return(true)
      allow(fcc_bar_instance).to receive(:deserialized?).with().and_return(true)

      expect(fcc_foo_instance).to receive(:before_validation!).once.with()
      expect(fcc_bar_instance).to receive(:before_validation!).once.with()
      instance._flex_columns_before_validation!
    end

    it "should call through on before_save to only flex column objects that say they need it" do
      instance = @klass.new
      allow(@fcc_foo).to receive(:requires_serialization_on_save?).with(instance).and_return(false)
      allow(@fcc_bar).to receive(:requires_serialization_on_save?).with(instance).and_return(false)
      instance._flex_columns_before_save!

      fcc_foo_instance = double("fcc_foo_instance")
      expect(@fcc_foo).to receive(:new).once.with(instance).and_return(fcc_foo_instance)
      instance._flex_column_owned_object_for(:foo).should be(fcc_foo_instance)
      allow(@fcc_foo).to receive(:requires_serialization_on_save?).with(instance).and_return(false)

      instance._flex_columns_before_save!


      fcc_bar_instance = double("fcc_bar_instance")
      expect(@fcc_bar).to receive(:new).once.with(instance).and_return(fcc_bar_instance)
      instance._flex_column_owned_object_for(:bar).should be(fcc_bar_instance)
      allow(@fcc_bar).to receive(:requires_serialization_on_save?).with(instance).and_return(true)

      expect(fcc_bar_instance).to receive(:before_save!).once.with()
      instance._flex_columns_before_save!

      allow(@fcc_foo).to receive(:requires_serialization_on_save?).with(instance).and_return(true)
      allow(@fcc_bar).to receive(:requires_serialization_on_save?).with(instance).and_return(true)

      expect(fcc_foo_instance).to receive(:before_save!).once.with()
      expect(fcc_bar_instance).to receive(:before_save!).once.with()
      instance._flex_columns_before_save!
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

    it "should create, and hold on to, flex-column objects properly" do
      instance = @klass.new

      fcc_foo_instance = double("fcc_foo_instance")
      expect(@fcc_foo).to receive(:new).once.with(instance).and_return(fcc_foo_instance)
      instance._flex_column_owned_object_for(:foo).should be(fcc_foo_instance)

      fcc_bar_instance = double("fcc_bar_instance")
      expect(@fcc_bar).to receive(:new).once.with(instance).and_return(fcc_bar_instance)
      instance._flex_column_owned_object_for(:bar).should be(fcc_bar_instance)

      instance._flex_column_owned_object_for(:foo).should be(fcc_foo_instance)
      instance._flex_column_owned_object_for(' bAr ').should be(fcc_bar_instance)
    end

    it "should re-create flex-column objects on reload, and call super and return its value" do
      @superclass.class_eval do
        def reload
          @reloads ||= 0
          @reloads += 1
          :reload_return_yo
        end

        def reloads
          @reloads ||= 0
        end
      end

      instance = @klass.new

      fcc_foo_instance = double("fcc_foo_instance")
      expect(@fcc_foo).to receive(:new).once.with(instance).and_return(fcc_foo_instance)
      instance._flex_column_owned_object_for(:foo).should be(fcc_foo_instance)

      fcc_bar_instance = double("fcc_bar_instance")
      expect(@fcc_bar).to receive(:new).once.with(instance).and_return(fcc_bar_instance)
      instance._flex_column_owned_object_for(:bar).should be(fcc_bar_instance)

      instance._flex_column_owned_object_for(:foo).should be(fcc_foo_instance)
      instance._flex_column_owned_object_for(:bar).should be(fcc_bar_instance)

      instance.reloads.should == 0
      instance.reload.should == :reload_return_yo
      instance.reloads.should == 1

      fcc_foo_instance_2 = double("fcc_foo_instance_2")
      expect(@fcc_foo).to receive(:new).once.with(instance).and_return(fcc_foo_instance_2)
      instance._flex_column_owned_object_for(:foo).should be(fcc_foo_instance_2)

      fcc_bar_instance_2 = double("fcc_bar_instance_2")
      expect(@fcc_bar).to receive(:new).once.with(instance).and_return(fcc_bar_instance_2)
      instance._flex_column_owned_object_for(:bar).should be(fcc_bar_instance_2)
    end

    it "should tell you what flex-column names have been defined" do
      @klass._all_flex_column_names.sort_by(&:to_s).should == [ :foo, :bar ].sort_by(&:to_s)
    end

    it "should answer whether a flex-column name has been defined" do
      @klass._has_flex_column_named?(:foo).should be
      @klass._has_flex_column_named?('foo').should be
      @klass._has_flex_column_named?(:bar).should be
      @klass._has_flex_column_named?('bar').should be
      @klass._has_flex_column_named?(:baz).should_not be
      @klass._has_flex_column_named?('baz').should_not be
    end

    it "should normalize column names properly" do
      @klass._flex_column_normalize_name(:baz).should == :baz
      @klass._flex_column_normalize_name(:' bAz ').should == :baz
      @klass._flex_column_normalize_name('   bAZ ').should == :baz
    end

    it "should create flex-column objects upon request that aren't attached to a model instance" do
      fcc_foo_instance = double("fcc_foo_instance")
      expect(@fcc_foo).to receive(:new).once.with(nil).and_return(fcc_foo_instance)
      @klass.create_flex_object_from(:foo, nil).should be(fcc_foo_instance)

      fcc_foo_instance = double("fcc_foo_instance")
      expect(@fcc_foo).to receive(:new).once.with(" JSON string ").and_return(fcc_foo_instance)
      @klass.create_flex_object_from(:foo, " JSON string ").should be(fcc_foo_instance)

      fcc_bar_instance_1 = double("fcc_bar_instance_1")
      expect(@fcc_bar).to receive(:new).once.with(nil).and_return(fcc_bar_instance_1)
      fcc_bar_instance_2 = double("fcc_bar_instance_2")
      expect(@fcc_bar).to receive(:new).once.with(" JSON string ").and_return(fcc_bar_instance_2)
      @klass.create_flex_objects_from(:bar, [ nil, " JSON string " ]).should == [ fcc_bar_instance_1, fcc_bar_instance_2 ]
    end
  end
end
