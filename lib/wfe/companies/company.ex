defmodule Wfe.Companies.Company do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "companies" do
    field :name, :string
    field :ats, :string

    has_many :jobs, Wfe.Jobs.Job

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(company, attrs) do
    company
    |> cast(attrs, [:name, :ats])
    |> validate_required([:name, :ats])
    |> unique_constraint(:name)
  end
end
