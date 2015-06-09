Logger.configure(level: :info)
ExUnit.start exclude: [:array_type,
                       :decimal_type,
                       :update_with_join,
                       :delete_with_join,
                       :right_join,
                       :modify_column,
                       :remove_column]

# Configure Ecto for support and tests
Application.put_env(:ecto, :primary_key_type, :id)

# Load support files
Code.require_file "../../deps/ecto/integration_test/support/repo.exs", __DIR__

# Basic test repo
alias Ecto.Integration.TestRepo

Application.put_env(:sqlite_ecto, TestRepo,
  adapter: Sqlite.Ecto,
  database: "/tmp/test_repo.db",
  size: 1, max_overflow: 0)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :sqlite_ecto
end

# Pool repo for transaction and lock tests
alias Ecto.Integration.PoolRepo

Application.put_env(:sqlite_ecto, PoolRepo,
  adapter: Sqlite.Ecto,
  database: "/tmp/test_repo.db",
  size: 10)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :sqlite_ecto
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
Code.require_file "../../deps/ecto/integration_test/support/models.exs", __DIR__
Code.require_file "../../deps/ecto/integration_test/support/migration.exs", __DIR__

# Load up the repository, start it, and run migrations
_   = Ecto.Storage.down(TestRepo)
:ok = Ecto.Storage.up(TestRepo)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
