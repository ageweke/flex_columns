# flex_columns

Schema-free, structured storage inside a RDBMS. Use a `VARCHAR`, `TEXT`, `CLOB`, `BLOB`, or `BINARY` column in your
schema to store structured data in JSON, while still letting you run validations against that data, build methods on
top of it, and automatically delegate it to your models. Far more powerful than ActiveRecord's built-in serialization
mechanism, `flex_columns` gives you the freedom of schemaless databases inside a proven RDBMS.

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

    class User < ActiveRecord::Base


...and then you can write code like so:

    user = User.find(...)

    user.user_attributes.french?   # access directly from the column
    user.ua_visit_count            # :prefix prefixed the delegated method names with the desired string

    user.visit_count = 'foo'       # sets an invalid value
    user.save                      # => false; user isn't valid
    user.errors.keys               # => :'user_attributes.visit_count'
    user.errors[:'user_attributes.visit_count'] # => [ 'must be a number' ]

There's lots more, too:

* Bulk operations, for avoiding ActiveRecord instantiation (efficiently operate using raw +select_all+ and +activerecord-import+ or similar systems)
* Transparently compresses JSON data in the column using GZip, if it's typed as binary (`BINARY`, `VARBINARY`, `CLOB`, etc.); you can fully control this, or turn it off if you want
*
