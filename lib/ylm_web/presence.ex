defmodule YlmWeb.Presence do
  @moduledoc """
  Provides presence tracking to sessions.
  """
  use Phoenix.Presence,
    otp_app: :ylm,
    pubsub_server: Ylm.PubSub
end
