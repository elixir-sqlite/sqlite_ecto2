IO.puts """
IMPORTANT: If you see many tests fail with a warning about cell-wise
default values not being supported in SQLite, please run the script

  ./integration/hack_out_incompatible_tests.sh

and then run `mix test` again.

"""

ExUnit.start()
