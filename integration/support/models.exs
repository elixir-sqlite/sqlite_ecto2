defmodule Ecto.Integration.Model do
  defmacro __using__(_) do
    quote do
      use Ecto.Model

      type =
        Application.get_env(:ecto, :primary_key_type) ||
        raise ":primary_key_type not set in :ecto application"
      @primary_key {:id, type, autogenerate: true}
      @foreign_key_type type
    end
  end
end

defmodule Sqlite.Ecto.Integration.Post do
  @moduledoc """
  This module is used to test:

    * Overall functionality
    * Overall types
    * Non-null timestamps
    * Relationships

  """
  use Ecto.Integration.Model

  schema "posts" do
    field :counter, :id # Same as integer
    field :title, :string
    field :text, :binary
    field :temp, :string, default: "temp", virtual: true
    field :public, :boolean, default: true
    field :cost, :decimal
    field :visits, :integer
    field :intensity, :float
    field :bid, :binary_id
    field :uuid, Ecto.UUID, autogenerate: true
    has_many :comments, Sqlite.Ecto.Integration.Comment
    has_one :permalink, Sqlite.Ecto.Integration.Permalink
    has_many :comments_authors, through: [:comments, :author]
    timestamps
  end
end

defmodule Sqlite.Ecto.Integration.PostUsecTimestamps do
  @moduledoc """
  This module is used to test:

    * Usec timestamps

  """
  use Ecto.Integration.Model

  schema "posts" do
    field :title, :string
    timestamps usec: true
  end
end

defmodule Sqlite.Ecto.Integration.Comment do
  @moduledoc """
  This module is used to test:

    * Optimistic lock
    * Relationships

  """
  use Ecto.Integration.Model

  schema "comments" do
    field :text, :string
    field :posted, :datetime
    field :lock_version, :integer, default: 1
    belongs_to :post, Sqlite.Ecto.Integration.Post
    belongs_to :author, Sqlite.Ecto.Integration.User
    has_one :post_permalink, through: [:post, :permalink]
  end

  optimistic_lock :lock_version
end

defmodule Sqlite.Ecto.Integration.Permalink do
  @moduledoc """
  This module is used to test:

    * Relationships

  """
  use Ecto.Integration.Model

  schema "permalinks" do
    field :url, :string
    belongs_to :post, Sqlite.Ecto.Integration.Post
    has_many :post_comments_authors, through: [:post, :comments_authors]
  end
end

defmodule Sqlite.Ecto.Integration.User do
  @moduledoc """
  This module is used to test:

    * Timestamps
    * Relationships

  """
  use Ecto.Integration.Model

  schema "users" do
    field :name, :string
    has_many :comments, Sqlite.Ecto.Integration.Comment, foreign_key: :author_id
    belongs_to :custom, Sqlite.Ecto.Integration.Custom, references: :bid, type: :binary_id
    timestamps
  end
end

defmodule Sqlite.Ecto.Integration.Custom do
  @moduledoc """
  This module is used to test:

    * binary_id primary key
    * Tying another schemas to an existing model

  Due to the second item, it must be a subset of posts.
  """
  use Ecto.Integration.Model

  @primary_key {:bid, :binary_id, autogenerate: true}
  schema "customs" do
  end
end

defmodule Sqlite.Ecto.Integration.Barebone do
  @moduledoc """
  This module is used to test:

    * A model wthout primary keys

  """
  use Ecto.Integration.Model

  @primary_key false
  schema "barebones" do
    field :num, :integer
  end
end

defmodule Sqlite.Ecto.Integration.Tag do
  @moduledoc """
  This module is used to test:

    * The array type

  """
  use Ecto.Integration.Model

  schema "tags" do
    field :ints, {:array, :integer}
    field :uuids, {:array, Ecto.UUID}
  end
end
