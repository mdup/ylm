defmodule Ylm.Sessions do
  @moduledoc """
  The Sessions context manages presentation sessions and participant states.
  """

  alias Ylm.Sessions.{Session, Participant}

  def new_session do
    %Session{
      id: generate_session_id(),
      current_slide: 1,
      participants: %{},
      messages: []
    }
  end

  def join_session(session, name) do
    participant_id = generate_participant_id()
    participant = %Participant{
      id: participant_id,
      name: name,
      slide_responses: %{},
      joined_at: DateTime.utc_now()
    }

    updated_participants = Map.put(session.participants, participant_id, participant)
    {%{session | participants: updated_participants}, participant_id}
  end

  def update_participant_status(session, participant_id, status, slide_number) when status in [:understand, :lost] do
    case Map.get(session.participants, participant_id) do
      nil ->
        {:error, :participant_not_found}
      participant ->
        updated_participant = Participant.set_response_for_slide(participant, slide_number, status)
        updated_participants = Map.put(session.participants, participant_id, updated_participant)
        {:ok, %{session | participants: updated_participants}}
    end
  end

  def clear_participant_response(session, participant_id, slide_number) do
    case Map.get(session.participants, participant_id) do
      nil ->
        {:error, :participant_not_found}
      participant ->
        updated_participant = Participant.clear_response_for_slide(participant, slide_number)
        updated_participants = Map.put(session.participants, participant_id, updated_participant)
        {:ok, %{session | participants: updated_participants}}
    end
  end

  def change_slide(session, slide_number) when is_integer(slide_number) and slide_number > 0 do
    # Don't reset participants - preserve their responses for all slides
    %{session | current_slide: slide_number}
  end

  def get_participants_by_status(session) do
    get_participants_by_status_for_slide(session, session.current_slide)
  end

  def get_participants_by_status_for_slide(session, slide_number) do
    understand = session.participants
    |> Enum.filter(fn {_id, p} ->
      Participant.get_response_for_slide(p, slide_number) == :understand
    end)
    |> Enum.map(fn {_id, p} -> p end)

    lost = session.participants
    |> Enum.filter(fn {_id, p} ->
      Participant.get_response_for_slide(p, slide_number) == :lost
    end)
    |> Enum.map(fn {_id, p} -> p end)

    %{understand: understand, lost: lost}
  end

  def add_message(session, participant_id, content) do
    case Map.get(session.participants, participant_id) do
      nil ->
        {:error, :participant_not_found}
      participant ->
        message = %{
          id: generate_message_id(),
          participant_name: participant.name,
          content: String.trim(content),
          timestamp: DateTime.utc_now()
        }

        # Handle sessions that don't have messages field (migration compatibility)
        current_messages = Map.get(session, :messages, [])

        # Keep only the last 50 messages to prevent memory issues
        updated_messages = [message | current_messages] |> Enum.take(50)
        {:ok, %{session | messages: updated_messages}}
    end
  end

  def get_recent_messages(session, limit \\ 10) do
    # Handle sessions that don't have messages field (migration compatibility)
    messages = Map.get(session, :messages, [])

    messages
    |> Enum.take(limit)
    |> Enum.reverse()
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode64(padding: false)
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> String.slice(0..7)
    |> String.upcase()
  end

  defp generate_participant_id do
    System.unique_integer([:positive])
    |> Integer.to_string()
  end

  defp generate_message_id do
    System.unique_integer([:positive])
    |> Integer.to_string()
  end
end