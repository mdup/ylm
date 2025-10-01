defmodule Ylm.Sessions.Participant do
  @moduledoc "Represents a participant in a session"

  defstruct [:id, :name, :slide_responses, :joined_at]

  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    slide_responses: %{integer() => :understand | :lost},
    joined_at: DateTime.t()
  }

  @doc """
  Get the participant's response for a specific slide
  """
  def get_response_for_slide(participant, slide_number) do
    Map.get(participant.slide_responses, slide_number)
  end

  @doc """
  Set the participant's response for a specific slide
  """
  def set_response_for_slide(participant, slide_number, status) when status in [:understand, :lost] do
    updated_responses = Map.put(participant.slide_responses, slide_number, status)
    %{participant | slide_responses: updated_responses}
  end

  @doc """
  Clear the participant's response for a specific slide
  """
  def clear_response_for_slide(participant, slide_number) do
    updated_responses = Map.delete(participant.slide_responses, slide_number)
    %{participant | slide_responses: updated_responses}
  end
end