# flex_columns

Schema-free, structured storage inside a RDBMS. Use a `VARCHAR`, `TEXT`, `CLOB`, `BLOB`, or `BINARY` column in your
schema to store structured data in JSON, while still letting you run validations against that data, build methods on
top of it, and automatically delegate it to your models. Far more powerful than ActiveRecord's built-in serialization
mechanism, `flex_columns` gives you the freedom of schemaless databases inside a proven RDBMS.

### Example

As an example &mdash; assume table `users` has a `CLOB` column `user_attributes`:

    class User < ActiveRecord::Base
      flex_column :user_attributes do
        field :
