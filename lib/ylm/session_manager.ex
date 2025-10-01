defmodule Ylm.SessionManager do
  @moduledoc """
  GenServer to manage active presentation sessions
  """
  use GenServer

  alias Ylm.Sessions

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def create_session do
    GenServer.call(__MODULE__, :create_session)
  end

  def get_session(session_id) do
    GenServer.call(__MODULE__, {:get_session, session_id})
  end

  def join_session(session_id, name) do
    GenServer.call(__MODULE__, {:join_session, session_id, name})
  end

  def update_participant_status(session_id, participant_id, status, slide_number) do
    GenServer.call(__MODULE__, {:update_status, session_id, participant_id, status, slide_number})
  end

  def clear_participant_response(session_id, participant_id, slide_number) do
    GenServer.call(__MODULE__, {:clear_response, session_id, participant_id, slide_number})
  end

  def change_slide(session_id, slide_number) do
    GenServer.call(__MODULE__, {:change_slide, session_id, slide_number})
  end

  # Server Callbacks

  @impl true
  def init(_) do
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call(:create_session, _from, state) do
    session = Sessions.new_session()
    updated_state = put_in(state, [:sessions, session.id], session)
    {:reply, session, updated_state}
  end

  @impl true
  def handle_call({:get_session, session_id}, _from, state) do
    session = get_in(state, [:sessions, session_id])
    {:reply, session, state}
  end

  @impl true
  def handle_call({:join_session, session_id, name}, _from, state) do
    case get_in(state, [:sessions, session_id]) do
      nil ->
        {:reply, {:error, :session_not_found}, state}
      session ->
        {updated_session, participant_id} = Sessions.join_session(session, name)
        updated_state = put_in(state, [:sessions, session_id], updated_session)
        {:reply, {:ok, updated_session, participant_id}, updated_state}
    end
  end

  @impl true
  def handle_call({:update_status, session_id, participant_id, status, slide_number}, _from, state) do
    case get_in(state, [:sessions, session_id]) do
      nil ->
        {:reply, {:error, :session_not_found}, state}
      session ->
        case Sessions.update_participant_status(session, participant_id, status, slide_number) do
          {:ok, updated_session} ->
            updated_state = put_in(state, [:sessions, session_id], updated_session)
            {:reply, {:ok, updated_session}, updated_state}
          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:clear_response, session_id, participant_id, slide_number}, _from, state) do
    case get_in(state, [:sessions, session_id]) do
      nil ->
        {:reply, {:error, :session_not_found}, state}
      session ->
        case Sessions.clear_participant_response(session, participant_id, slide_number) do
          {:ok, updated_session} ->
            updated_state = put_in(state, [:sessions, session_id], updated_session)
            {:reply, {:ok, updated_session}, updated_state}
          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:change_slide, session_id, slide_number}, _from, state) do
    case get_in(state, [:sessions, session_id]) do
      nil ->
        {:reply, {:error, :session_not_found}, state}
      session ->
        updated_session = Sessions.change_slide(session, slide_number)
        updated_state = put_in(state, [:sessions, session_id], updated_session)
        {:reply, {:ok, updated_session}, updated_state}
    end
  end
end