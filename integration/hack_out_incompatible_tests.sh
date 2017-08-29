#!/bin/bash

# Ugly but necessary hack to disable certain untagged tests that can't be
# supported by SQLite.

# WARNING: There is trailing whitespace on the `sed` line that must be retained.

if [ "$(uname)" == "Darwin" ] ; then

sed -i "" '/test "insert all/ i\ 
  @tag :insert_cell_wise_defaults
' deps/ecto/integration_test/cases/repo.exs

sed -i "" '/failing child foreign key/ i\ 
  @tag :foreign_key_constraint
' deps/ecto/integration_test/cases/repo.exs

sed -i "" '/test "Repo.insert_all escape/ i\ 
  @tag :insert_cell_wise_defaults
' deps/ecto/integration_test/sql/sql.exs

sed -i "" '/subqueries with map and select expression/ i\ 
  @tag :map_boolean_in_subquery
' deps/ecto/integration_test/sql/subquery.exs

sed -i "" '/subqueries with map update and select expression/ i\ 
  @tag :map_boolean_in_subquery
' deps/ecto/integration_test/sql/subquery.exs

else

sed -i '/test "insert all/ i @tag :insert_cell_wise_defaults' deps/ecto/integration_test/cases/repo.exs

sed -i '/failing child foreign key/ i @tag :foreign_key_constraint' deps/ecto/integration_test/cases/repo.exs

sed -i '/test "Repo.insert_all escape/ i @tag :insert_cell_wise_defaults' deps/ecto/integration_test/sql/sql.exs

sed -i '/subqueries with map and select expression/ i @tag :map_boolean_in_subquery' deps/ecto/integration_test/sql/subquery.exs

sed -i '/subqueries with map update and select expression/ i @tag :map_boolean_in_subquery' deps/ecto/integration_test/sql/subquery.exs

fi
