defmodule YlmWeb.PresenterLive do
  use YlmWeb, :live_view

  alias Ylm.Sessions
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    session = Sessions.new_session()

    # Subscribe to updates for this session
    PubSub.subscribe(Ylm.PubSub, "session:#{session.id}")

    {:ok,
     socket
     |> assign(:session, session)
     |> assign(:participants_by_status, Sessions.get_participants_by_status(session))
     |> assign(:page_title, "Presenter - YLM")}
  end

  @impl true
  def handle_event("change_slide", %{"direction" => direction}, socket) do
    current_slide = socket.assigns.session.current_slide
    new_slide = case direction do
      "next" -> current_slide + 1
      "prev" -> max(1, current_slide - 1)
    end

    updated_session = Sessions.change_slide(socket.assigns.session, new_slide)

    # Broadcast slide change to all participants
    PubSub.broadcast(Ylm.PubSub, "session:#{updated_session.id}", {:slide_changed, new_slide})

    {:noreply,
     socket
     |> assign(:session, updated_session)
     |> assign(:participants_by_status, Sessions.get_participants_by_status(updated_session))}
  end

  @impl true
  def handle_info({:participant_joined, name, _participant_id}, socket) do
    {updated_session, _} = Sessions.join_session(socket.assigns.session, name)

    {:noreply,
     socket
     |> assign(:session, updated_session)
     |> assign(:participants_by_status, Sessions.get_participants_by_status(updated_session))}
  end

  @impl true
  def handle_info({:status_updated, participant_id, status}, socket) do
    case Sessions.update_participant_status(socket.assigns.session, participant_id, status) do
      {:ok, updated_session} ->
        {:noreply,
         socket
         |> assign(:session, updated_session)
         |> assign(:participants_by_status, Sessions.get_participants_by_status(updated_session))}
      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100 p-8">
      <div class="max-w-6xl mx-auto">
        <div class="bg-white rounded-lg shadow-lg p-8 mb-8">
          <div class="text-center">
            <h1 class="text-6xl font-bold text-gray-800 mb-4">
              Slide <%= @session.current_slide %>
            </h1>
            <div class="flex justify-center gap-4 mb-6">
              <button
                phx-click="change_slide"
                phx-value-direction="prev"
                class="px-6 py-2 bg-gray-500 text-white rounded-lg hover:bg-gray-600 transition"
                disabled={@session.current_slide == 1}
              >
                ← Previous
              </button>
              <button
                phx-click="change_slide"
                phx-value-direction="next"
                class="px-6 py-2 bg-gray-500 text-white rounded-lg hover:bg-gray-600 transition"
              >
                Next →
              </button>
            </div>
            <div class="text-sm text-gray-600">
              Session Code: <span class="font-mono font-bold text-lg"><%= @session.id %></span>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-8">
          <div class="bg-green-50 rounded-lg p-6">
            <h2 class="text-2xl font-bold text-green-800 mb-4 flex items-center">
              <svg class="w-6 h-6 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              I Understand (<%= length(@participants_by_status.understand) %>)
            </h2>
            <div class="space-y-2">
              <%= for participant <- @participants_by_status.understand do %>
                <div class="bg-white rounded px-4 py-2 text-gray-800">
                  <%= participant.name %>
                </div>
              <% end %>
              <%= if Enum.empty?(@participants_by_status.understand) do %>
                <div class="text-gray-500 italic">No participants yet</div>
              <% end %>
            </div>
          </div>

          <div class="bg-red-50 rounded-lg p-6">
            <h2 class="text-2xl font-bold text-red-800 mb-4 flex items-center">
              <svg class="w-6 h-6 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              You Lost Me (<%= length(@participants_by_status.lost) %>)
            </h2>
            <div class="space-y-2">
              <%= for participant <- @participants_by_status.lost do %>
                <div class="bg-white rounded px-4 py-2 text-gray-800">
                  <%= participant.name %>
                </div>
              <% end %>
              <%= if Enum.empty?(@participants_by_status.lost) do %>
                <div class="text-gray-500 italic">No participants yet</div>
              <% end %>
            </div>
          </div>
        </div>

        <div class="mt-8 text-center text-gray-600">
          <p class="text-lg">
            Total Participants: <%= map_size(@session.participants) %>
          </p>
        </div>
      </div>
    </div>
    """
  end
end