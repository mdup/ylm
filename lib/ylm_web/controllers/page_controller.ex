defmodule YlmWeb.PageController do
  use YlmWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
