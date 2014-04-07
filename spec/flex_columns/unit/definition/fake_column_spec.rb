describe ::FlexColumns::Definition::FakeColumn do
  it "should have the right properties" do
    c = ::FlexColumns::Definition::FakeColumn.new(:foo)
    c.name.should == :foo
    c.null.should == true
    c.type.should == :string
  end
end
