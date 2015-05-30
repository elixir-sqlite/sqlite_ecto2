Logger.configure(level: :info)
ExUnit.start exclude: [:array_type,
                       :update_with_join,
                       :delete_with_join,
                       :right_outer_join]

# Load support files
Code.require_file "support/repo.exs", __DIR__

# Basic test repo
alias Sqlite.Ecto.Integration.TestRepo

Application.put_env(:sqlite_ecto, TestRepo,
  adapter: Sqlite.Ecto,
  database: "/tmp/test_repo.db",
  size: 1, max_overflow: 0)

defmodule Sqlite.Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :sqlite_ecto
end

# Pool repo for transaction and lock tests
alias Sqlite.Ecto.Integration.PoolRepo

Application.put_env(:sqlite_ecto, PoolRepo,
  adapter: Sqlite.Ecto,
  database: "/tmp/test_repo.db",
  size: 10)

defmodule Sqlite.Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :sqlite_ecto

  def lock_for_update, do: "FOR UPDATE"
end

defmodule Sqlite.Ecto.Integration.Case do
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
Code.require_file "support/models.exs", __DIR__
Code.require_file "support/migration.exs", __DIR__

# Load up the repository, start it, and run migrations
_   = Ecto.Storage.down(TestRepo)
:ok = Ecto.Storage.up(TestRepo)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link

:ok = Ecto.Migrator.up(TestRepo, 0, Sqlite.Ecto.Integration.Migration, log: false)
