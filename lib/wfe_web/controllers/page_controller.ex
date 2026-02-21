defmodule WfeWeb.PageController do
  use WfeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
