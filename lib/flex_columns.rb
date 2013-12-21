require 'active_record'
require "flex_columns/version"
require "flex_columns/active_record/base"

# The FlexColumns module. Currently, we use this for nothing more than a namespace for our various classes.
module FlexColumns
end

# Include a very few methods into ActiveRecord::Base. If you declare a flex column using +flex_column+, or include
# flex columns using +include_flex_columns_from+, we include additional modules into your model class that do more
# work. This strategy lets us make sure we add as little as possible to ActiveRecord::Base for classes that don't
# have anything to do with flex columns.
class ActiveRecord::Base
  include FlexColumns::ActiveRecord::Base
end
