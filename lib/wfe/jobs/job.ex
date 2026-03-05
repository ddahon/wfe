defmodule Wfe.Jobs.Job do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "jobs" do
    field :external_id, :string
    field :title, :string
    field :description, :string
    field :location, :string
    field :link, :string
    field :posted_at, :utc_datetime
    field :content_hash, :string

    belongs_to :company, Wfe.Companies.Company

    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [:external_id, :title, :description, :location, :link, :posted_at, :company_id])
    |> validate_required([:external_id, :title, :company_id])
    |> put_content_hash()
    |> unique_constraint([:company_id, :external_id])
    |> foreign_key_constraint(:company_id)
  end

  defp put_content_hash(changeset) do
    title = get_field(changeset, :title)
    desc = get_field(changeset, :description)
    put_change(changeset, :content_hash, Wfe.Jobs.ContentHash.compute(title, desc))
  end
end
