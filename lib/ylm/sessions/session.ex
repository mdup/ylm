defmodule Ylm.Sessions.Session do
  @moduledoc "Represents a presentation session"

  defstruct [:id, :current_slide, :participants, :messages]

  @type message :: %{
    id: String.t(),
    participant_name: String.t(),
    content: String.t(),
    timestamp: DateTime.t()
  }

  @type t :: %__MODULE__{
    id: String.t(),
    current_slide: integer(),
    participants: %{String.t() => Ylm.Sessions.Participant.t()},
    messages: [message()]
  }
end