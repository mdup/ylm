defmodule Ylm.Repo do
  use Ecto.Repo,
    otp_app: :ylm,
    adapter: Ecto.Adapters.Postgres
end
