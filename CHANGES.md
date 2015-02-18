# `flex_columns` Changelog

## 1.0.9, 2015-02-18

* Full support for ActiveRecord 4.2.x.
* Bumped versions of Rails and Ruby that we test against to much more up-to-date ones.

## 1.0.8, 2014-07-06

* Fixed an issue where you couldn't migrate a flex_column into existence with a migration &mdash; because if you
declared a flex_column on a table that existed but a column that didn't, you would get an exception
(`FlexColumns::Errors::NoSuchColumnError`) immediately.
* Bumped versions of Rails and Ruby that we test against to much more up-to-date ones.

## 1.0.7, 2014-04-07

* Fixed an issue where, if you defined a model class when its table didn't exist, and then created its table while the Ruby process was still running, you still couldn't access any flex-column attributes &mdash; because we would simply skip defining them entirely if the table didn't exist. Now, we define them, assuming the columns exist and are of type `:string` (and `null`able) if the table doesn't exist, and replace them with the actual column definition once the table exists. (You need to call `.reset_column_information` on the model class to make this happen, just as you do with any changes to the underlying table of an ActiveRecord model.)

## 1.0.6, 2014-04-07

* Fixed an issue where Float::INFINITY and Float::NaN could not be stored in a flex column.

## 1.0.5, 2014-04-03

* Fixed an issue where boolean fields would fail to validate if `:null => false` was passed and their value was `false`.
* Fixed an issue where integer fields would fail to validate if `nil` was allowed (that is, `:null => false` was _not_ passed) and yet `nil` was stored in them.

## 1.0.4, 2014-03-31

* Fixed an incompatibility with Rails 4.0.3 or 4.0.4 due to a change in the way ActiveRecord::Base#method missing works. The way we were handling this (by double-implementing `_flex_column_object_for` and trying to use `super` to delegate one to the other) was pretty gross, anyway; this fix is much more solid.
* Fixed a problem where `flex_columns` would raise an exception if the underlying table didn't exist. This could cause problems trying to migrate a table into existence when its model already existed and declared a flex column.
