require 'active_record'
require "flex_columns/version"
require "flex_columns/active_record/base"

module FlexColumns
end

class ActiveRecord::Base
  include FlexColumns::ActiveRecord::Base
end
