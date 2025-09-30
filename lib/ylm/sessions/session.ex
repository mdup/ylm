defmodule Ylm.Sessions.Session do
  @moduledoc "Represents a presentation session"

  defstruct [:id, :current_slide, :participants]

  @type t :: %__MODULE__{
    id: String.t(),
    current_slide: integer(),
    participants: %{String.t() => Ylm.Sessions.Participant.t()}
  }
end