# `flex_columns` Changelog

## 1.0.4, 2014-03-31

* Fixed an incompatibility with Rails 4.0.3 or 4.0.4 due to a change in the way ActiveRecord::Base#method missing works. The way we were handling this (by double-implementing `_flex_column_object_for` and trying to use `super` to delegate one to the other) was pretty gross, anyway; this fix is much more solid.
* Fixed a problem where `flex_columns` would raise an exception if the underlying table didn't exist. This could cause problems trying to migrate a table into existence when its model already existed and declared a flex column.
