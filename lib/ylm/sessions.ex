defmodule Ylm.Sessions do
  @moduledoc """
  The Sessions context manages presentation sessions and participant states.
  """

  alias Ylm.Sessions.{Session, Participant}

  def new_session do
    %Session{
      id: generate_session_id(),
      current_slide: 1,
      participants: %{}
    }
  end

  def join_session(session, name) do
    participant_id = generate_participant_id()
    participant = %Participant{
      id: participant_id,
      name: name,
      status: nil,
      joined_at: DateTime.utc_now()
    }

    updated_participants = Map.put(session.participants, participant_id, participant)
    {%{session | participants: updated_participants}, participant_id}
  end

  def update_participant_status(session, participant_id, status) when status in [:understand, :lost] do
    case Map.get(session.participants, participant_id) do
      nil ->
        {:error, :participant_not_found}
      participant ->
        updated_participant = %{participant | status: status}
        updated_participants = Map.put(session.participants, participant_id, updated_participant)
        {:ok, %{session | participants: updated_participants}}
    end
  end

  def change_slide(session, slide_number) when is_integer(slide_number) and slide_number > 0 do
    # Reset all participant statuses when changing slides
    reset_participants = session.participants
    |> Enum.map(fn {id, participant} -> {id, %{participant | status: nil}} end)
    |> Map.new()

    %{session | current_slide: slide_number, participants: reset_participants}
  end

  def get_participants_by_status(session) do
    understand = session.participants
    |> Enum.filter(fn {_id, p} -> p.status == :understand end)
    |> Enum.map(fn {_id, p} -> p end)

    lost = session.participants
    |> Enum.filter(fn {_id, p} -> p.status == :lost end)
    |> Enum.map(fn {_id, p} -> p end)

    %{understand: understand, lost: lost}
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
end