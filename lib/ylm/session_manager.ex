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

  def add_message(session_id, participant_id, content) do
    GenServer.call(__MODULE__, {:add_message, session_id, participant_id, content})
  end

  def mark_presenter_disconnected(session_id) do
    GenServer.call(__MODULE__, {:mark_presenter_disconnected, session_id})
  end

  def register_presenter(session_id, presenter_pid) do
    GenServer.call(__MODULE__, {:register_presenter, session_id, presenter_pid})
  end

  # Server Callbacks

  @impl true
  def init(_) do
    {:ok, %{sessions: %{}, presenter_monitors: %{}}}
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

  @impl true
  def handle_call({:add_message, session_id, participant_id, content}, _from, state) do
    case get_in(state, [:sessions, session_id]) do
      nil ->
        {:reply, {:error, :session_not_found}, state}
      session ->
        case Sessions.add_message(session, participant_id, content) do
          {:ok, updated_session} ->
            updated_state = put_in(state, [:sessions, session_id], updated_session)
            {:reply, {:ok, updated_session}, updated_state}
          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:mark_presenter_disconnected, session_id}, _from, state) do
    case get_in(state, [:sessions, session_id]) do
      nil ->
        {:reply, :ok, state}
      session ->
        updated_session = Sessions.mark_presenter_disconnected(session)
        updated_state = put_in(state, [:sessions, session_id], updated_session)
        {:reply, :ok, updated_state}
    end
  end

  @impl true
  def handle_call({:register_presenter, session_id, presenter_pid}, _from, state) do
    require Logger
    # Monitor the presenter process
    ref = Process.monitor(presenter_pid)
    Logger.info("Registered presenter for session #{session_id}, monitor ref: #{inspect(ref)}")

    # Ensure presenter_monitors map exists (for backward compatibility)
    presenter_monitors = Map.get(state, :presenter_monitors, %{})

    # Store the monitor ref and session_id mapping
    updated_state = Map.put(state, :presenter_monitors, Map.put(presenter_monitors, ref, session_id))

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Ensure presenter_monitors exists
    presenter_monitors = Map.get(state, :presenter_monitors, %{})

    # Check if this was a presenter process
    case Map.get(presenter_monitors, ref) do
      nil ->
        # Not a presenter we're monitoring
        {:noreply, state}

      session_id ->
        require Logger
        Logger.info("Presenter disconnected for session #{session_id}, broadcasting to participants")

        # Presenter disconnected - mark session and broadcast
        case get_in(state, [:sessions, session_id]) do
          nil ->
            Logger.warning("Session #{session_id} not found when presenter disconnected")
            # Clean up monitor ref
            updated_monitors = Map.delete(presenter_monitors, ref)
            updated_state = Map.put(state, :presenter_monitors, updated_monitors)
            {:noreply, updated_state}

          session ->
            # Mark session as disconnected
            updated_session = Sessions.mark_presenter_disconnected(session)

            # Broadcast to participants
            result = Phoenix.PubSub.broadcast(
              Ylm.PubSub,
              "session:#{session_id}",
              :presenter_disconnected
            )
            Logger.info("Broadcast result: #{inspect(result)}")

            # Update state
            updated_monitors = Map.delete(presenter_monitors, ref)
            updated_state =
              state
              |> put_in([:sessions, session_id], updated_session)
              |> Map.put(:presenter_monitors, updated_monitors)

            {:noreply, updated_state}
        end
    end
  end
end