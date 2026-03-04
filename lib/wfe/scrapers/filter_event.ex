defmodule Wfe.Scrapers.FilterEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "filter_events" do
    field :external_id, :string
    field :title, :string
    field :location, :string
    field :link, :string
    field :outcome, :string
    field :reason, :string
    field :ats, :string
    field :run_id, Ecto.UUID

    belongs_to :company, Wfe.Companies.Company

    timestamps(type: :utc_datetime)
  end

  @valid_outcomes ~w(passed rejected)
  @valid_reasons ~w(ats_hint_remote ats_hint_onsite heuristic_pass heuristic_reject)

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :external_id,
      :title,
      :location,
      :link,
      :outcome,
      :reason,
      :ats,
      :run_id,
      :company_id
    ])
    |> validate_required([:external_id, :outcome, :reason, :ats, :run_id, :company_id])
    |> validate_inclusion(:outcome, @valid_outcomes)
    |> validate_inclusion(:reason, @valid_reasons)
    |> foreign_key_constraint(:company_id)
  end
end
