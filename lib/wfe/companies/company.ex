defmodule Wfe.Companies.Company do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "companies" do
    field :name, :string
    field :ats, :string
    field :ats_identifier, :string
    field :scrape_status, :string, default: "pending"
    field :scrape_error, :string
    field :last_scraped_at, :utc_datetime

    has_many :jobs, Wfe.Jobs.Job

    timestamps(type: :utc_datetime)
  end

  def changeset(company, attrs) do
    company
    |> cast(attrs, [:name, :ats, :ats_identifier, :scrape_status, :scrape_error, :last_scraped_at])
    |> validate_required([:name])
    |> validate_inclusion(:ats, ~w(greenhouse lever ashby), allow_nil: true)
  end
end
