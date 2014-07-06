require 'flex_columns'
require 'flex_columns/helpers/system_helpers'

describe "FlexColumns support for migrations" do
  include FlexColumns::Helpers::SystemHelpers

  before :each do
    @dh = FlexColumns::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!
  end

  after :each do
    migrate do
      drop_table :flexcols_spec_nonexistent_col rescue nil
    end
  end

  it "should not raise an error if a flex_column is declared for a column that doesn't exist on a model (yet)" do
    migrate do
      drop_table :flexcols_spec_nonexistent_col rescue nil
      create_table :flexcols_spec_nonexistent_col do |t|
        t.string :name
      end
    end

    define_model_class(:Nonexistent, 'flexcols_spec_nonexistent_col') do
      flex_column :something do
        field :some_data
      end
    end

    n1 = ::Nonexistent.new
    n1.name = "foo"
    n1.save!

    expect(n1.some_data).to be_nil
    expect(n1.something.some_data).to be_nil

    n1_again = ::Nonexistent.find(n1.id)
    expect(n1_again.name).to eq("foo")

    expect(n1_again.some_data).to be_nil
    expect(n1_again.something.some_data).to be_nil
  end

  it "should let you migrate a column into existence and have it work" do
    migrate do
      drop_table :flexcols_spec_nonexistent_col rescue nil
      create_table :flexcols_spec_nonexistent_col do |t|
        t.string :name
      end
    end

    define_model_class(:Nonexistent, 'flexcols_spec_nonexistent_col') do
      flex_column :something do
        field :some_data
      end
    end

    n1 = ::Nonexistent.new
    n1.name = "foo"
    n1.save!

    expect(n1.some_data).to be_nil
    expect(n1.something.some_data).to be_nil

    n1_again = ::Nonexistent.find(n1.id)
    expect(n1_again.name).to eq("foo")

    expect(n1_again.some_data).to be_nil
    expect(n1_again.something.some_data).to be_nil

    migrate do
      add_column :flexcols_spec_nonexistent_col, :something, :text
    end

    ::Nonexistent.reset_column_information

    n2 = ::Nonexistent.new
    n2.name = "bar"
    n2.some_data = "some_data for bar"
    n2.save!

    n2_again = ::Nonexistent.find(n2.id)
    expect(n2_again.name).to eq("bar")
    expect(n2_again.some_data).to eq("some_data for bar")
  end
end
