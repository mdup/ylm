defmodule YlmWeb.PresenterLive do
  use YlmWeb, :live_view

  alias Ylm.{Sessions, SessionManager}
  alias Phoenix.PubSub

  @impl true
  def mount(_params, _session, socket) do
    session = SessionManager.create_session()

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

    {:ok, updated_session} = SessionManager.change_slide(socket.assigns.session.id, new_slide)

    # Broadcast slide change to all participants
    PubSub.broadcast(Ylm.PubSub, "session:#{updated_session.id}", {:slide_changed, new_slide})

    {:noreply,
     socket
     |> assign(:session, updated_session)
     |> assign(:participants_by_status, Sessions.get_participants_by_status(updated_session))}
  end

  @impl true
  def handle_info({:participant_joined, _name, _participant_id}, socket) do
    # Get the updated session from the SessionManager
    updated_session = SessionManager.get_session(socket.assigns.session.id)

    {:noreply,
     socket
     |> assign(:session, updated_session)
     |> assign(:participants_by_status, Sessions.get_participants_by_status(updated_session))}
  end

  @impl true
  def handle_info({:status_updated, _participant_id, _status}, socket) do
    # Get the updated session from the SessionManager
    updated_session = SessionManager.get_session(socket.assigns.session.id)

    {:noreply,
     socket
     |> assign(:session, updated_session)
     |> assign(:participants_by_status, Sessions.get_participants_by_status(updated_session))}
  end

  @impl true
  def handle_info(_message, socket) do
    # Ignore other messages (like slide_changed which we already handled locally)
    {:noreply, socket}
  end

  # Helper function to get initials from a name
  defp get_initials(name) do
    name
    |> String.split()
    |> Enum.take(2)  # Take first two words
    |> Enum.map(&String.first(&1))
    |> Enum.map(&String.upcase(&1))
    |> Enum.join("")
  end

  # Helper function to generate QR code as data URI
  defp generate_qr_code(url) do
    require Logger
    Logger.info("Attempting to generate QR code for URL: #{url}")

    try do
      # Use the pipeline approach like in the documentation
      result = url
      |> QRCode.create()
      |> QRCode.render()

      Logger.info("Pipeline result type: #{inspect(elem(result, 0))}")

      # The result is {:ok, svg_string}
      case result do
        {:ok, svg_content} when is_binary(svg_content) ->
          Logger.info("Successfully got SVG content, length: #{String.length(svg_content)}")
          data_uri = "data:image/svg+xml;base64,#{Base.encode64(svg_content)}"
          Logger.info("Data URI created, total length: #{String.length(data_uri)}")
          data_uri

        {:error, reason} ->
          Logger.error("QR code generation failed: #{inspect(reason)}")
          nil

        other ->
          Logger.error("Unexpected result format: #{inspect(other)}")
          nil
      end
    rescue
      exception ->
        Logger.error("Exception generating QR code: #{inspect(exception)}")
        nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100 p-8">
      <div class="max-w-7xl mx-auto">
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
              <br>
              Join URL: <span class="font-mono text-sm text-blue-600">
                <%= YlmWeb.Endpoint.url() %>/join/<%= @session.id %>
              </span>
            </div>

            <!-- QR Code for Join URL -->
            <%
              join_url = "#{YlmWeb.Endpoint.url()}/join/#{@session.id}"
              qr_code_data = generate_qr_code(join_url)
            %>
            <%= if qr_code_data do %>
              <div class="mt-4 flex justify-center">
                <div class="bg-white p-4 rounded-lg shadow-md">
                  <img src={qr_code_data} alt="QR Code for join URL" class="w-32 h-32" />
                  <p class="text-xs text-gray-500 text-center mt-2">Scan to join</p>
                </div>
              </div>
            <% else %>
              <div class="mt-4 flex justify-center">
                <div class="bg-red-100 p-4 rounded-lg">
                  <p class="text-xs text-red-500 text-center">QR code failed to generate</p>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-8">
          <%
            total = map_size(@session.participants)
            understand_count = length(@participants_by_status.understand)
            lost_count = length(@participants_by_status.lost)
            understand_percentage = if total > 0, do: understand_count / total * 100, else: 0
            lost_percentage = if total > 0, do: lost_count / total * 100, else: 0
          %>

          <!-- I Understand Section -->
          <div class="bg-green-50 rounded-lg p-8">
            <h2 class="text-2xl font-bold text-green-800 mb-6 text-center">I Understand</h2>

            <!-- Progress Circle -->
            <div class="flex justify-center mb-6">
              <div class="relative">
                <svg class="w-48 h-48 transform -rotate-90">
                  <!-- Background circle -->
                  <circle
                    cx="96"
                    cy="96"
                    r="88"
                    stroke="#e5e7eb"
                    stroke-width="16"
                    fill="none"
                  />
                  <!-- Progress circle -->
                  <circle
                    cx="96"
                    cy="96"
                    r="88"
                    stroke="#10b981"
                    stroke-width="16"
                    fill="none"
                    stroke-dasharray={"#{88 * 2 * 3.14159}"}
                    stroke-dashoffset={"#{88 * 2 * 3.14159 * (1 - understand_percentage / 100)}"}
                    class="transition-all duration-500"
                  />
                </svg>
                <div class="absolute inset-0 flex flex-col items-center justify-center">
                  <span class="text-6xl font-bold text-green-700">
                    <%= understand_count %>
                  </span>
                  <span class="text-lg text-gray-600">
                    <%= if total > 0 do %>
                      of <%= total %>
                    <% else %>
                      waiting...
                    <% end %>
                  </span>
                </div>
              </div>
            </div>

            <!-- Participant list -->
            <div class="space-y-2 max-h-64 overflow-y-auto">
              <%= for participant <- @participants_by_status.understand do %>
                <div class="bg-white rounded px-4 py-2 text-gray-800">
                  <%= participant.name %>
                </div>
              <% end %>
              <%= if Enum.empty?(@participants_by_status.understand) do %>
                <div class="text-gray-500 italic text-center">No responses yet</div>
              <% end %>
            </div>
          </div>

          <!-- You Lost Me Section -->
          <div class="bg-red-50 rounded-lg p-8">
            <h2 class="text-2xl font-bold text-red-800 mb-6 text-center">You Lost Me</h2>

            <!-- Progress Circle -->
            <div class="flex justify-center mb-6">
              <div class="relative">
                <svg class="w-48 h-48 transform -rotate-90">
                  <!-- Background circle -->
                  <circle
                    cx="96"
                    cy="96"
                    r="88"
                    stroke="#e5e7eb"
                    stroke-width="16"
                    fill="none"
                  />
                  <!-- Progress circle -->
                  <circle
                    cx="96"
                    cy="96"
                    r="88"
                    stroke="#ef4444"
                    stroke-width="16"
                    fill="none"
                    stroke-dasharray={"#{88 * 2 * 3.14159}"}
                    stroke-dashoffset={"#{88 * 2 * 3.14159 * (1 - lost_percentage / 100)}"}
                    class="transition-all duration-500"
                  />
                </svg>
                <div class="absolute inset-0 flex flex-col items-center justify-center">
                  <span class="text-6xl font-bold text-red-700">
                    <%= lost_count %>
                  </span>
                  <span class="text-lg text-gray-600">
                    <%= if total > 0 do %>
                      of <%= total %>
                    <% else %>
                      waiting...
                    <% end %>
                  </span>
                </div>
              </div>
            </div>

            <!-- Participant list -->
            <div class="space-y-2 max-h-64 overflow-y-auto">
              <%= for participant <- @participants_by_status.lost do %>
                <div class="bg-white rounded px-4 py-2 text-gray-800">
                  <%= participant.name %>
                </div>
              <% end %>
              <%= if Enum.empty?(@participants_by_status.lost) do %>
                <div class="text-gray-500 italic text-center">No responses yet</div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Connected Participants -->
        <%= if total > 0 do %>
          <div class="mt-8">
            <h3 class="text-xl font-bold text-gray-800 mb-4 text-center">Connected Participants</h3>
            <div class="flex flex-wrap justify-center gap-3">
              <%= for {_id, participant} <- @session.participants do %>
                <%
                  current_response = Ylm.Sessions.Participant.get_response_for_slide(participant, @session.current_slide)
                  border_color = case current_response do
                    :understand -> "border-green-500 bg-green-50"
                    :lost -> "border-red-500 bg-red-50"
                    nil -> "border-gray-300 bg-gray-50"
                  end
                %>
                <div class={"w-12 h-12 rounded-full flex items-center justify-center border-2 #{border_color}"}>
                  <span class="text-sm font-semibold text-gray-700">
                    <%= get_initials(participant.name) %>
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <div class="mt-8 text-center text-gray-600">
          <p class="text-lg">
            Total Participants: <span class="font-bold text-2xl"><%= total %></span>
            <%= if total > 0 do %>
              <span class="mx-4">|</span>
              Responded: <span class="font-bold text-2xl"><%= understand_count + lost_count %></span>
            <% end %>
          </p>
        </div>
      </div>
    </div>
    """
  end
end