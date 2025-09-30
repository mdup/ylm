defmodule YlmWeb.ParticipantLive do
  use YlmWeb, :live_view

  alias Phoenix.PubSub
  alias Ylm.SessionManager

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:session_id, session_id)
     |> assign(:participant_id, nil)
     |> assign(:participant_name, "")
     |> assign(:current_slide, 1)
     |> assign(:status, nil)
     |> assign(:joined, false)
     |> assign(:page_title, "Join Session - YLM")}
  end

  @impl true
  def handle_event("update_name", %{"value" => name}, socket) when is_binary(name) do
    {:noreply, assign(socket, :participant_name, name)}
  end

  @impl true
  def handle_event("update_name", %{"key" => _key, "value" => name}, socket) do
    {:noreply, assign(socket, :participant_name, name)}
  end

  @impl true
  def handle_event("join", _params, socket) do
    name = String.trim(socket.assigns.participant_name)

    if String.length(name) > 0 do
      # Join the session through SessionManager
      case SessionManager.join_session(socket.assigns.session_id, name) do
        {:ok, _updated_session, participant_id} ->
          # Subscribe to session updates
          PubSub.subscribe(Ylm.PubSub, "session:#{socket.assigns.session_id}")

          # Notify presenter of new participant
          PubSub.broadcast(
            Ylm.PubSub,
            "session:#{socket.assigns.session_id}",
            {:participant_joined, name, participant_id}
          )

          {:noreply,
           socket
           |> assign(:participant_id, participant_id)
           |> assign(:joined, true)
           |> assign(:page_title, "#{name} - YLM")}

        {:error, :session_not_found} ->
          {:noreply, put_flash(socket, :error, "Session not found. Please check the code.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please enter your name")}
    end
  end

  @impl true
  def handle_event("set_status", %{"status" => status}, socket) do
    status_atom = String.to_existing_atom(status)

    # Update status through SessionManager
    case SessionManager.update_participant_status(
      socket.assigns.session_id,
      socket.assigns.participant_id,
      status_atom
    ) do
      {:ok, _updated_session} ->
        # Broadcast status update to presenter
        PubSub.broadcast(
          Ylm.PubSub,
          "session:#{socket.assigns.session_id}",
          {:status_updated, socket.assigns.participant_id, status_atom}
        )

        {:noreply, assign(socket, :status, status_atom)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:slide_changed, slide_number}, socket) do
    {:noreply,
     socket
     |> assign(:current_slide, slide_number)
     |> assign(:status, nil)}  # Reset status on slide change
  end

  @impl true
  def handle_info(_message, socket) do
    # Ignore other messages (like participant_joined which is meant for presenter)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 flex items-center justify-center p-4">
      <%= if not @joined do %>
        <div class="bg-white rounded-lg shadow-xl p-8 max-w-md w-full">
          <h1 class="text-3xl font-bold text-gray-800 mb-6 text-center">Join Session</h1>
          <form phx-submit="join" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Your Name
              </label>
              <input
                type="text"
                name="name"
                value={@participant_name}
                phx-keyup="update_name"
                class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                placeholder="Enter your name"
                required
              />
            </div>
            <div class="text-center text-sm text-gray-600">
              Session: <span class="font-mono font-bold"><%= @session_id %></span>
            </div>
            <button
              type="submit"
              class="w-full bg-blue-600 text-white py-2 px-4 rounded-lg hover:bg-blue-700 transition font-medium"
            >
              Join Session
            </button>
          </form>
        </div>
      <% else %>
        <div class="bg-white rounded-lg shadow-xl p-8 max-w-lg w-full">
          <div class="text-center mb-8">
            <h2 class="text-4xl font-bold text-gray-800 mb-2">
              Slide <%= @current_slide %>
            </h2>
            <p class="text-gray-600">Hi, <%= @participant_name %>!</p>
          </div>

          <div class="space-y-4">
            <button
              phx-click="set_status"
              phx-value-status="understand"
              class={"w-full py-4 px-6 rounded-lg text-lg font-medium transition " <>
                if @status == :understand,
                  do: "bg-green-600 text-white ring-4 ring-green-300",
                  else: "bg-green-100 text-green-800 hover:bg-green-200"}
            >
              <div class="flex items-center justify-center">
                <svg class="w-6 h-6 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                I Understand
              </div>
            </button>

            <button
              phx-click="set_status"
              phx-value-status="lost"
              class={"w-full py-4 px-6 rounded-lg text-lg font-medium transition " <>
                if @status == :lost,
                  do: "bg-red-600 text-white ring-4 ring-red-300",
                  else: "bg-red-100 text-red-800 hover:bg-red-200"}
            >
              <div class="flex items-center justify-center">
                <svg class="w-6 h-6 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                You Lost Me
              </div>
            </button>
          </div>

          <%= if @status do %>
            <div class="mt-6 text-center text-sm text-gray-600">
              Your response has been recorded.
              <br>
              You can change it at any time.
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end