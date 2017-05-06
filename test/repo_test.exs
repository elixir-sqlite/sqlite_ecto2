Code.require_file "support/schemas.exs", __DIR__

defmodule Sqlite.Ecto2.RepoTest do
  use Ecto.Integration.Case, async: Application.get_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Sqlite.Ecto2.Test.MiscTypes

  test "preserves time with microseconds" do
    TestRepo.insert!(%MiscTypes{name: "hello", start_time: ~T(09:33:51.130422)})
    assert [%MiscTypes{name: "hello", start_time: ~T(09:33:51.130422)}] =
      TestRepo.all from mt in MiscTypes
  end

  test "handles time with milliseconds" do
    # Looks like Ecto doesn't provide a way for adapter to see the subsecond
    # precision of timestamps so we always fill out the time with zeros.
    TestRepo.insert!(%MiscTypes{name: "hello", start_time: ~T(09:33:51.529)})
    assert [%MiscTypes{name: "hello", start_time: ~T(09:33:51.529000)}] =
      TestRepo.all from mt in MiscTypes
  end
end
