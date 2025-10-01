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
     |> assign(:message_text, "")
     |> assign(:message_cooldown_until, nil)
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
  def handle_event("update_message", %{"value" => message}, socket) do
    {:noreply, assign(socket, :message_text, message)}
  end

  @impl true
  def handle_event("update_message", %{"key" => _key, "value" => message}, socket) do
    {:noreply, assign(socket, :message_text, message)}
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    message = String.trim(socket.assigns.message_text)
    now = DateTime.utc_now()

    # Check cooldown
    cooldown_active? =
      case socket.assigns.message_cooldown_until do
        nil -> false
        cooldown_time -> DateTime.compare(now, cooldown_time) == :lt
      end

    cond do
      cooldown_active? ->
        {:noreply, socket}

      String.length(message) > 0 ->
        case SessionManager.add_message(
               socket.assigns.session_id,
               socket.assigns.participant_id,
               message
             ) do
          {:ok, _updated_session} ->
            # Broadcast message update to presenter
            PubSub.broadcast(
              Ylm.PubSub,
              "session:#{socket.assigns.session_id}",
              {:message_sent, socket.assigns.participant_id, message}
            )

            # Set cooldown to 10 seconds from now
            cooldown_until = DateTime.add(now, 10, :second)

            # Schedule the first cooldown tick to update UI
            Process.send_after(self(), :tick_cooldown, 1000)

            {:noreply,
             socket
             |> assign(:message_text, "")
             |> assign(:message_cooldown_until, cooldown_until)}

          _ ->
            {:noreply, socket}
        end

      true ->
        {:noreply, socket}
    end
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

          # Get any previous response for the current slide
          initial_status =
            get_participant_status_for_slide(
              socket.assigns.session_id,
              participant_id,
              socket.assigns.current_slide
            )

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
           |> assign(:status, initial_status)
           |> assign(:message_text, "")
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
    current_status = socket.assigns.status

    # If clicking the same button, toggle it off (remove response)
    new_status = if current_status == status_atom, do: nil, else: status_atom

    case new_status do
      nil ->
        # Clear the response for this slide
        case SessionManager.clear_participant_response(
               socket.assigns.session_id,
               socket.assigns.participant_id,
               socket.assigns.current_slide
             ) do
          {:ok, _updated_session} ->
            # Broadcast status update to presenter
            PubSub.broadcast(
              Ylm.PubSub,
              "session:#{socket.assigns.session_id}",
              {:status_updated, socket.assigns.participant_id, nil}
            )

            {:noreply, assign(socket, :status, nil)}

          _ ->
            {:noreply, socket}
        end

      status ->
        # Update status through SessionManager for the current slide
        case SessionManager.update_participant_status(
               socket.assigns.session_id,
               socket.assigns.participant_id,
               status,
               socket.assigns.current_slide
             ) do
          {:ok, _updated_session} ->
            # Broadcast status update to presenter
            PubSub.broadcast(
              Ylm.PubSub,
              "session:#{socket.assigns.session_id}",
              {:status_updated, socket.assigns.participant_id, status}
            )

            {:noreply, assign(socket, :status, status)}

          _ ->
            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_info({:slide_changed, slide_number}, socket) do
    # Get the participant's previous response for this slide (if any)
    previous_status =
      get_participant_status_for_slide(
        socket.assigns.session_id,
        socket.assigns.participant_id,
        slide_number
      )

    {:noreply,
     socket
     |> assign(:current_slide, slide_number)
     |> assign(:status, previous_status)}
  end

  @impl true
  def handle_info(:tick_cooldown, socket) do
    # Check if cooldown expired
    now = DateTime.utc_now()

    cooldown_expired? = case socket.assigns.message_cooldown_until do
      nil -> true
      cooldown_time -> DateTime.compare(now, cooldown_time) != :lt
    end

    socket = if cooldown_expired? do
      # Cooldown finished, clear it
      assign(socket, :message_cooldown_until, nil)
    else
      # Still in cooldown, schedule next tick
      Process.send_after(self(), :tick_cooldown, 1000)
      socket
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(_message, socket) do
    # Ignore other messages (like participant_joined which is meant for presenter)
    {:noreply, socket}
  end

  # Helper function to get participant's status for a specific slide
  defp get_participant_status_for_slide(session_id, participant_id, slide_number) do
    case SessionManager.get_session(session_id) do
      nil ->
        nil

      session ->
        case Map.get(session.participants, participant_id) do
          nil ->
            nil

          participant ->
            Ylm.Sessions.Participant.get_response_for_slide(participant, slide_number)
        end
    end
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
              Session: <span class="font-mono font-bold">{@session_id}</span>
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
              Slide {@current_slide}
            </h2>
            <p class="text-gray-600">Hi, {@participant_name}!</p>
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
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
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
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                You Lost Me
              </div>
            </button>
          </div>

          <%= if @status do %>
            <div class="mt-6 text-center text-sm text-gray-600">
              Your response has been recorded. <br /> You can change it at any time.
            </div>
          <% end %>

    <!-- Message Input -->
          <div class="mt-8 pt-6 border-t border-gray-200">
            <% now = DateTime.utc_now()

            cooldown_active? =
              case @message_cooldown_until do
                nil -> false
                cooldown_time -> DateTime.compare(now, cooldown_time) == :lt
              end

            button_disabled = String.trim(@message_text) == "" or cooldown_active? %>
            <form phx-submit="send_message" class="space-y-3">
              <div>
                <label class="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                  Send a public message
                  <div class="group relative">
                    <svg
                      class="w-4 h-4 text-gray-400 hover:text-gray-600 cursor-help"
                      fill="currentColor"
                      viewBox="0 0 20 20"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                        clip-rule="evenodd"
                      />
                    </svg>
                    <div class="absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-3 py-2 bg-gray-900 text-white text-xs rounded-lg whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none z-10">
                      This message will appear on the presentation screen and will be visible to everyone.
                      <div class="absolute top-full left-1/2 transform -translate-x-1/2 -mt-1 border-4 border-transparent border-t-gray-900">
                      </div>
                    </div>
                  </div>
                </label>
                <input
                  type="text"
                  name="message"
                  value={@message_text}
                  phx-keyup="update_message"
                  disabled={cooldown_active?}
                  class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                  placeholder="Type your message..."
                  maxlength="200"
                />
              </div>
              <button
                type="submit"
                disabled={button_disabled}
                class="w-full bg-blue-600 text-white py-2 px-4 rounded-lg hover:bg-blue-700 transition font-medium disabled:bg-gray-400 disabled:cursor-not-allowed"
              >
                Send Message
              </button>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end

