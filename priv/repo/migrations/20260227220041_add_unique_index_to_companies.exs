defmodule Wfe.Repo.Migrations.AddUniqueIndexToCompanies do
  use Ecto.Migration

  def change do
    create unique_index(:companies, [:ats, :ats_identifier],
             name: :companies_ats_ats_identifier_index
           )
  end
end
