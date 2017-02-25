#!/bin/bash

# Ugly but necessary hack to disable certain untagged tests that can't be
# supported by SQLite.

# Also: Hack around https://github.com/mmzeeman/esqlite/issues/33 until that is
# fully resolved.

# WARNING: There is trailing whitespace on the `sed` line that must be retained.

if [ `uname` == "Darwin" ] ; then

sed -i "" '/test "insert all/ i\ 
  @tag :insert_cell_wise_defaults
' deps/ecto/integration_test/cases/repo.exs

sed -i "" '/test "starts repo with different names/ i\ 
  @tag :crash_prone
' deps/ecto/integration_test/cases/pool.exs

else

sed -i '/test "insert all/ i @tag :insert_cell_wise_defaults' deps/ecto/integration_test/cases/repo.exs

sed -i '/test "starts repo with different names/ i @tag :crash_prone' deps/ecto/integration_test/cases/pool.exs

fi
