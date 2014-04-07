# flex_columns

Schema-free, structured storage inside a RDBMS. Use a `VARCHAR`, `TEXT`, `CLOB`, `BLOB`, or `BINARY` column in your
schema to store structured data in JSON, while still letting you run validations against that data, build methods on
top of it, and automatically delegate it to your models. Far more powerful than ActiveRecord's built-in serialization
mechanism, `flex_columns` gives you the freedom of schemaless databases inside a proven RDBMS.

Combined with [`low_card_tables`](https://github.com/ageweke/low_card_tables), allows a RDBMS to represent a wide
variety of data efficiently and with a great deal of flexibility &mdash; build your projects rapidly and effectively
while relying on the most reliable, manageable, proven data engines out there.

Supported platforms:

* Ruby 1.8.7, 1.9.3, 2.0.0, and JRuby 1.7.6.
* ActiveRecord 3.0.20, 3.1.12, 3.2.16, and 4.0.2. (Should be compatible with future versions, as well...just sits on top of the public API of ActiveRecord.)
* Tested against MySQL, PostgreSQL, and SQLite 3. (Should be compatible with all RDBMSes supported by ActiveRecord.)

Current build status: ![Current Build Status](https://api.travis-ci.org/ageweke/flex_columns.png?branch=master)

### Installing flex_columns

    # Gemfile
    gem 'flex_columns'

### Example

As an example &mdash; assume table `users` has a `CLOB` column `user_attributes`:

    class User < ActiveRecord::Base
      ...
      flex_column :user_attributes do
        field :locale
        field :comments_display_mode
        field :custom_page_color
        field :nickname
      end
      ...
    end

You can now write code like:

    user = User.find(...)
    user.locale = :fr_FR

    case user.comments_display_mode
    when 'threaded' then ...
    when 'linear' then ...
    end

### Robust Example

As a snapshot of all possibilities:

    # Assume we're storing the JSON in a wholly separate table, so we don't have to load it unless we need it...
    class UserDetails < ActiveRecord::Base
      flex_column :user_attributes,
        :compress => 100,        # try compressing any JSON >= 100 bytes, but only store compressed if it's smaller
        :visibility => :private, # attributes are private by default
        :prefix => :ua,          # sets a prefix for methods delegated from the outer class
        :unknown_fields => :delete # if DB contains fields not declared here, delete those keys when saving
      do
        # automatically adds validations requiring a string that's non-nil
        field :locale, :string, :null => false
        # automatically adds validations requiring the value to be one of the listed values
        field :comments_display_mode, :enum => %w{threaded linear collapsed}
        # in the JSON in the database, the key will be 'cpc', not 'custom_page_color', to save space
        field :custom_page_color, :json => :cpc
        field :nickname
        field :visit_count, :integer

        # Use the full gamut of Rails validations -- they will run automatically when saving a User
        validates :custom_page_color, :format => { :with => /^\#[0-9a-f]{6}/i, :message => 'must be a valid HTML hex color' }

        # Define custom methods...
        def french?
          [ :fr_FR, :fr_CA ].include?(locale)
        end

        # +super+ works correctly in all cases
        def visit_count
          super || 0
        end

        # You can also access attributes using Hash syntax
        def increment_visit_count!
          self[:visit_count] += 1
        end
      end
    end

    # And now transparently include it into our User class...
    class User < ActiveRecord::Base
      has_one :user_details

      include_flex_columns_from :user_details
    end

...and then you can write code like so:

    user = User.find(...)

    user.user_attributes.french?   # access directly from the column
    user.ua_visit_count            # :prefix prefixed the delegated method names with the desired string

    user.visit_count = 'foo'       # sets an invalid value
    user.save                      # => false; user isn't valid
    user.errors.keys               # => :'user_attributes.visit_count'
    user.errors[:'user_attributes.visit_count'] # => [ 'must be a number' ]

There's lots more, too:

* Complete validations support: the flex-column object includes ActiveModel::Validations, so every single Rails validation (or custom validations) will work perfectly
* Bulk operations, for avoiding ActiveRecord instantiation (efficiently operate using raw `select_all` and `activerecord-import` or similar systems)
* Transparently compresses JSON data in the column using GZip, if it's typed as binary (`BINARY`, `VARBINARY`, `CLOB`, etc.); you can fully control this, or turn it off if you want
* Happily allows definition and redefinition of flex columns at any time, for full dynamism and compatibility with development mode of Rails
* Rich error hierarchy and detailed exception messages &mdash; you will know exactly what went wrong when something goes wrong
* Include flex columns across associations, with control over exactly what's delegated and visibility of those methods (public or private)
* Control whether attribute methods generated are public (default) or private (to encourage encapsulation)
* "Types": automatically adds validations that require fields to comply with database types like `:integer`, `:string`, `:timestamp`, etc.
* Decide whether to preserve (the default) or delete keys from the underlying JSON that aren't defined in the flex column &mdash; lets you ensure database data is of the highest quality, or be compatible with any other storage mechanisms

### Documentation

# Documentation is on [the Wiki](https://github.com/ageweke/flex_columns/wiki)!
