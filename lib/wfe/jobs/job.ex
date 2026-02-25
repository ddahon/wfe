defmodule Wfe.Jobs.Job do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "jobs" do
    field :title, :string
    field :description, :string
    field :location, :string
    field :link, :string
    field :posted_at, :utc_datetime

    belongs_to :company, Wfe.Companies.Company
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:title, :description, :location, :link, :posted_at, :company_id])
    |> validate_required([:title, :company_id])
    |> foreign_key_constraint(:company_id)
  end
end
