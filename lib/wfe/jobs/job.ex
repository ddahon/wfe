defmodule Wfe.Jobs.Job do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "jobs" do
    field :external_id, :string
    field :title, :string
    field :description, :string
    # Raw location string as received from the ATS. Kept verbatim for
    # debugging classifier misses.
    field :location, :string
    # Normalised hiring region, set by RegionFilter. Query on this.
    field :region, :string
    field :link, :string
    field :posted_at, :utc_datetime
    field :content_hash, :string

    belongs_to :company, Wfe.Companies.Company

    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :external_id,
      :title,
      :description,
      :location,
      :region,
      :link,
      :posted_at,
      :company_id
    ])
    |> validate_required([:external_id, :title, :company_id])
    |> validate_inclusion(:region, Wfe.Jobs.RegionClassifier.regions() |> Enum.map(&Wfe.Jobs.RegionClassifier.region_name/1),
      message: "must be a recognised region"
    )
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
