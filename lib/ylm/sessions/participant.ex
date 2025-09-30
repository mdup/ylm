defmodule Ylm.Sessions.Participant do
  @moduledoc "Represents a participant in a session"

  defstruct [:id, :name, :status, :joined_at]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    status: :understand | :lost | nil,
    joined_at: DateTime.t()
  }
end