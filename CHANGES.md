# `flex_columns` Changelog

## 1.0.6, 2014-04-07

* Fixed an issue where Float::INFINITY and Float::NaN could not be stored in a flex column.

## 1.0.5, 2014-04-03

* Fixed an issue where boolean fields would fail to validate if `:null => false` was passed and their value was `false`.
* Fixed an issue where integer fields would fail to validate if `nil` was allowed (that is, `:null => false` was _not_ passed) and yet `nil` was stored in them.

## 1.0.4, 2014-03-31

* Fixed an incompatibility with Rails 4.0.3 or 4.0.4 due to a change in the way ActiveRecord::Base#method missing works. The way we were handling this (by double-implementing `_flex_column_object_for` and trying to use `super` to delegate one to the other) was pretty gross, anyway; this fix is much more solid.
* Fixed a problem where `flex_columns` would raise an exception if the underlying table didn't exist. This could cause problems trying to migrate a table into existence when its model already existed and declared a flex column.
