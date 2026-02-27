defmodule Wfe.Scrapers do
  @scrapers %{
    "greenhouse" => Wfe.Scrapers.Greenhouse,
    "lever" => Wfe.Scrapers.Lever,
    "ashby" => Wfe.Scrapers.Ashby,
    "workable" => Wfe.Scrapers.Workable,
    "recruitee" => Wfe.Scrapers.Recruitee
  }

  def supported_ats, do: Map.keys(@scrapers)

  def fetch_jobs(%{ats: ats} = company) do
    case Map.fetch(@scrapers, ats) do
      {:ok, mod} -> mod.fetch_jobs(company)
      :error -> {:error, {:unsupported_ats, ats}}
    end
  end
end
