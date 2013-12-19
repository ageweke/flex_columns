require 'flex_columns'

describe FlexColumns::Util::StringUtils do
  def klass
    FlexColumns::Util::StringUtils
  end

  it "should return its input for nil or short strings" do
    klass.abbreviated_string(nil).should == nil
    klass.abbreviated_string("").should == ""
    klass.abbreviated_string("    ").should == "    "
    klass.abbreviated_string("abc").should == "abc"
    klass.abbreviated_string("a" * 100).should == "a" * 100
  end

  it "should abbreviate long strings in the middle" do
    s = ("a" * 48) + ("b" * 5) + ("c" * 48)
    klass.abbreviated_string(s).should == ("a" * 48) + "..." + ("c" * 48)

    s = ("a" * 100_000) + "XX" + ("c" * 48)
    klass.abbreviated_string(s).should == ("a" * 48) + "..." + ("c" * 48)
  end
end
