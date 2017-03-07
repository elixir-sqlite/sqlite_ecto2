#!/bin/bash

# Ugly but necessary hack to disable certain untagged tests that can't be
# supported by SQLite.

# WARNING: There is trailing whitespace on the `sed` line that must be retained.

if [ `uname` == "Darwin" ] ; then

sed -i "" '/test "insert all/ i\ 
  @tag :insert_cell_wise_defaults
' deps/ecto/integration_test/cases/repo.exs

sed -i "" '/test "Repo.insert_all escape/ i\ 
  @tag :insert_cell_wise_defaults
' deps/ecto/integration_test/sql/sql.exs

else

sed -i '/test "insert all/ i @tag :insert_cell_wise_defaults' deps/ecto/integration_test/cases/repo.exs

sed -i '/test "Repo.insert_all escape/ i @tag :insert_cell_wise_defaults' deps/ecto/integration_test/sql/sql.exs

fi

# Backport this change until we catch up to that point in time (15 Feb 2016):
# https://github.com/elixir-ecto/ecto/commit/235c099a7856eb4451ccfbaede249a59d20b0c66#diff-3079a35f77dacc7bdd7cc2e69c39a886
if [ `uname` == "Darwin" ] ; then

sed -i '' '62s/TestRepo/PoolRepo/' deps/ecto/integration_test/sql/transaction.exs

else

sed -i '62s/TestRepo/PoolRepo/' deps/ecto/integration_test/sql/transaction.exs

fi
