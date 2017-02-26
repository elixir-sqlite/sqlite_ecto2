Logger.configure(level: :info)
ExUnit.start exclude: [:array_type,
                       :strict_savepoint,
                       :update_with_join,
                       :delete_with_join,
                       :foreign_key_constraint,
                       :modify_column,
                       :modify_foreign_key,
                       :prefix,
                       :remove_column,
                       :rename_column,
                       :right_join,
                       :unique_constraint,
                       :uses_usec,
                       :insert_cell_wise_defaults]

# Configure Ecto for support and tests
Application.put_env(:ecto, :primary_key_type, :id)

# Old Ecto files don't compile cleanly in Elixir 1.4, so we disable warnings first.
case System.version() do
  "1.4." <> _ -> Code.compiler_options(warnings_as_errors: false)
  _ -> :ok
end

# Load support files
Code.require_file "../../deps/ecto/integration_test/support/repo.exs", __DIR__

# Basic test repo
alias Ecto.Integration.TestRepo

Application.put_env(:ecto, TestRepo,
  adapter: Sqlite.Ecto,
  database: "/tmp/test_repo.db",
  pool: Ecto.Adapters.SQL.Sandbox)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :ecto
end

# Pool repo for transaction and lock tests
alias Ecto.Integration.PoolRepo

Application.put_env(:ecto, PoolRepo,
  adapter: Sqlite.Ecto,
  pool: DBConnection.Poolboy,
  database: "/tmp/test_repo.db",
  pool_size: 10)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup_all do
    Ecto.Adapters.SQL.begin_test_transaction(TestRepo, [])
    on_exit fn -> Ecto.Adapters.SQL.rollback_test_transaction(TestRepo, []) end
    :ok
  end

  setup do
    Ecto.Adapters.SQL.restart_test_transaction(TestRepo, [])
    :ok
  end
end

# Load support models and migration
Code.require_file "../../deps/ecto/integration_test/support/schemas.exs", __DIR__
Code.require_file "../../deps/ecto/integration_test/support/migration.exs", __DIR__

# Load up the repository, start it, and run migrations
_   = Ecto.Storage.down(TestRepo)
:ok = Ecto.Storage.up(TestRepo)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
Process.flag(:trap_exit, true)
