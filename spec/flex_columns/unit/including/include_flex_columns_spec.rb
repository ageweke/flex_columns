require 'flex_columns'

describe FlexColumns::Including::IncludeFlexColumns do
  before :each do
    @klass = Class.new { include FlexColumns::Including::IncludeFlexColumns }
  end

  describe "#_flex_column_included_object_for" do
    it "should raise an error if there is no appropriate association" do
      allow(@klass).to receive(:_flex_column_is_included_from).with(:foo).and_return(nil)
      allow(@klass).to receive(:name).with().and_return("klassname")
      instance = @klass.new

      lambda { instance._flex_column_included_object_for(:foo) }.should raise_error(FlexColumns::Errors::NoSuchColumnError, /klassname.*foo/i)
    end

    it "should invoke the right method on the right object if the association is already there" do
      allow(@klass).to receive(:_flex_column_is_included_from).with(:colname).and_return(:assocname)
      instance = @klass.new

      association_object = double("association_object")
      allow(instance).to receive(:assocname).with().and_return(association_object)
      allow(association_object).to receive(:colname).and_return(:baz)

      instance._flex_column_included_object_for(:colname).should == :baz
    end

    it "should create the associated object if necessary" do
      allow(@klass).to receive(:_flex_column_is_included_from).with(:colname).and_return(:assocname)
      instance = @klass.new

      association_object = double("association_object")
      allow(instance).to receive(:assocname).with().and_return(nil)
      allow(instance).to receive(:build_assocname).with().and_return(association_object)
      allow(association_object).to receive(:colname).and_return(:baz)

      instance._flex_column_included_object_for(:colname).should == :baz
    end
  end

  it "should return a singular DynamicMethodsModule on _flex_columns_include_flex_columns_dynamic_methods_module" do
    dmm = double("dmm")
    expect(FlexColumns::Util::DynamicMethodsModule).to receive(:new).once.with(@klass, :FlexColumnsIncludedColumnsMethods).and_return(dmm)
    @klass._flex_columns_include_flex_columns_dynamic_methods_module.should be(dmm)
    @klass._flex_columns_include_flex_columns_dynamic_methods_module.should be(dmm)
  end

  describe "#include_flex_columns_from" do
    before :each do
      @assoc1 = double("assoc1")
      allow(@assoc1).to receive(:name).with().and_return(:assoc1)
      allow(@assoc1).to receive(:macro).with().and_return(:has_one)
      @assoc2 = double("assoc2")
      allow(@assoc2).to receive(:name).with().and_return(:assoc2)
      allow(@assoc2).to receive(:macro).with().and_return(:belongs_to)

      allow(@klass).to receive(:reflect_on_association).with(:assoc1).and_return(@assoc1)
      allow(@klass).to receive(:reflect_on_association).with(:assoc2).and_return(@assoc2)

      allow(@klass).to receive(:reflect_on_all_associations).with().and_return([ @assoc1, @assoc2 ])
    end

    it "should validate its options properly" do
      lambda { @klass.include_flex_columns_from(:foo, :bar => :baz) }.should raise_error(ArgumentError)
      lambda { @klass.include_flex_columns_from(:foo, :prefix => 123) }.should raise_error(ArgumentError)
      lambda { @klass.include_flex_columns_from(:foo, :visibility => :bonk) }.should raise_error(ArgumentError)
      lambda { @klass.include_flex_columns_from(:foo, :delegate => :yes) }.should raise_error(ArgumentError)
    end

    it "should raise if there is no such association" do
      allow(@klass).to receive(:reflect_on_association).with(:foo).and_return(nil)
      lambda { @klass.include_flex_columns_from(:foo) }.should raise_error(ArgumentError, /foo.*assoc1.*assoc2/mi)
    end

    it "should raise if the association is of the wrong type" do
      allow(@assoc1).to receive(:macro).with().and_return(:has_many)
      lambda { @klass.include_flex_columns_from(:assoc1) }.should raise_error(ArgumentError, /assoc1.*has_many/mi)
    end

    it "should raise if the target class does not respond to #has_any_flex_columns?" do
      association_class = double("association_class")
      allow(association_class).to receive(:name).with().and_return("acname")
      allow(@assoc2).to receive(:klass).with().and_return(association_class)
      allow(association_class).to receive(:respond_to?).with(:has_any_flex_columns?).and_return(false)

      lambda { @klass.include_flex_columns_from(:assoc2) }.should raise_error(ArgumentError, /assoc2.*acname/mi)
    end

    it "should raise if the target class returns false from #has_any_flex_columns?" do
      association_class = double("association_class")
      allow(association_class).to receive(:name).with().and_return("acname")
      allow(@assoc2).to receive(:klass).with().and_return(association_class)
      allow(association_class).to receive(:has_any_flex_columns?).with().and_return(false)

      lambda { @klass.include_flex_columns_from(:assoc2) }.should raise_error(ArgumentError, /assoc2.*acname/mi)
    end

    it "should call through to the target flex-column class with provided options" do
      dmm = double("dmm")
      expect(FlexColumns::Util::DynamicMethodsModule).to receive(:new).once.with(@klass, :FlexColumnsIncludedColumnsMethods).and_return(dmm)

      ac1 = double("ac1")
      allow(@assoc1).to receive(:klass).with().and_return(ac1)
      allow(ac1).to receive(:has_any_flex_columns?).with().and_return(true)
      allow(ac1).to receive(:_all_flex_column_names).with().and_return([ :ac1fc1, :ac1fc2 ])

      ac1fc1_fcc = double("ac1fc1_fcc")
      expect(ac1fc1_fcc).to receive(:include_fields_into).once.ordered.with(dmm, :assoc1, @klass, :prefix => 'abz', :delegate => false, :visibility => :private)
      allow(ac1).to receive(:_flex_column_class_for).with(:ac1fc1).and_return(ac1fc1_fcc)
      ac1fc2_fcc = double("ac1fc2_fcc")
      expect(ac1fc2_fcc).to receive(:include_fields_into).once.ordered.with(dmm, :assoc1, @klass, :prefix => 'abz', :delegate => false, :visibility => :private)
      allow(ac1).to receive(:_flex_column_class_for).with(:ac1fc2).and_return(ac1fc2_fcc)

      ac2 = double("ac2")
      allow(@assoc2).to receive(:klass).with().and_return(ac2)
      allow(ac2).to receive(:has_any_flex_columns?).with().and_return(true)
      allow(ac2).to receive(:_all_flex_column_names).with().and_return([ :ac2fc1, :ac2fc2 ])

      ac2fc1_fcc = double("ac2fc1_fcc")
      expect(ac2fc1_fcc).to receive(:include_fields_into).once.ordered.with(dmm, :assoc2, @klass, :prefix => 'abz', :delegate => false, :visibility => :private)
      allow(ac2).to receive(:_flex_column_class_for).with(:ac2fc1).and_return(ac2fc1_fcc)
      ac2fc2_fcc = double("ac2fc2_fcc")
      expect(ac2fc2_fcc).to receive(:include_fields_into).once.ordered.with(dmm, :assoc2, @klass, :prefix => 'abz', :delegate => false, :visibility => :private)
      allow(ac2).to receive(:_flex_column_class_for).with(:ac2fc2).and_return(ac2fc2_fcc)

      @klass.include_flex_columns_from(:assoc1, :assoc2, :prefix => 'abz', :delegate => false, :visibility => :private)
    end
  end
end
