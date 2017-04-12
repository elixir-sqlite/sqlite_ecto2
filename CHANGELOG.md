# Changelog for v2.0

This is a major rewrite of the previously-existing [`sqlite_ecto`]((https://github.com/jazzyb/sqlite_ecto) that adds support for Ecto 2.1+.


## v2.0.0-dev.4

_unreleased_

* Port documentation from v1 `sqlite_ecto` repo to this repo.


## v2.0.0-dev.3

_11 April 2017_

## Bug fixes

* Requires sqlitex version 1.3.2 which includes an important bug fix (https://github.com/mmmries/sqlitex/pull/59).


## v2.0.0-dev.2

_26 March 2017_

## Bug fixes

* **BREAKING CHANGE:** Use the name `Sqlite.Ecto2` consistently in API names. Discontinue use of name `Sqlite.Ecto` (without the `2`)
* Ensure db_connection app is started before relying on it.


## v2.0.0-dev.1

_21 March 2017_

Initial public release of version 2.0 (alpha quality).


## Previous versions

* See the CHANGELOG.md [for the v1.x series](https://github.com/jazzyb/sqlite_ecto/blob/master/CHANGELOG.md)
