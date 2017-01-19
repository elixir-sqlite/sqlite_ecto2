defmodule Sqlite.DbConnection.Error do
  defexception [:message, :sqlite, :postgres]

  # TODO: Retrofit to actual SQLite error schema.

  def message(e) do
    if kw = e.postgres do
      "#{kw[:severity]} (#{kw[:code]}): #{kw[:message]}"
    else
      e.message
    end
  end

  def exception([postgres: fields]) do
    fields = Enum.into(fields, %{})
             |> Map.put(:pg_code, fields[:code])
             |> Map.update!(:code, &Sqlite.DbConnection.ErrorCode.code_to_name/1)

    %Sqlite.DbConnection.Error{postgres: fields}
  end

  def exception(arg) do
    super(arg)
  end
end
