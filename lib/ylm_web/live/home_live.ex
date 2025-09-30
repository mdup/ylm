defmodule YlmWeb.HomeLive do
  use YlmWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:session_code, "")
     |> assign(:page_title, "You Lost Me - Interactive Presentation Feedback")}
  end

  @impl true
  def handle_event("update_code", %{"code" => code}, socket) do
    {:noreply, assign(socket, :session_code, code)}
  end

  @impl true
  def handle_event("join_session", _params, socket) do
    code = String.trim(socket.assigns.session_code)
    if String.length(code) > 0 do
      {:noreply, push_navigate(socket, to: ~p"/join/#{code}")}
    else
      {:noreply, put_flash(socket, :error, "Please enter a session code")}
    end
  end

  @impl true
  def handle_event("start_presenting", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/presenter")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-indigo-500 via-purple-500 to-pink-500 flex items-center justify-center p-4">
      <div class="max-w-4xl w-full">
        <div class="text-center mb-12">
          <h1 class="text-6xl font-bold text-white mb-4">You Lost Me</h1>
          <p class="text-xl text-white/90">Interactive Presentation Feedback in Real-Time</p>
        </div>

        <div class="grid md:grid-cols-2 gap-8">
          <!-- Presenter Card -->
          <div class="bg-white rounded-2xl shadow-2xl p-8">
            <div class="text-center">
              <svg class="w-16 h-16 mx-auto mb-4 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
              </svg>
              <h2 class="text-2xl font-bold text-gray-800 mb-4">Start Presenting</h2>
              <p class="text-gray-600 mb-6">
                Create a new session and get real-time feedback from your audience
              </p>
              <button
                phx-click="start_presenting"
                class="w-full bg-indigo-600 text-white py-3 px-6 rounded-lg hover:bg-indigo-700 transition font-medium"
              >
                Start New Session
              </button>
            </div>
          </div>

          <!-- Participant Card -->
          <div class="bg-white rounded-2xl shadow-2xl p-8">
            <div class="text-center">
              <svg class="w-16 h-16 mx-auto mb-4 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
              </svg>
              <h2 class="text-2xl font-bold text-gray-800 mb-4">Join Session</h2>
              <p class="text-gray-600 mb-6">
                Enter a session code to provide feedback during a presentation
              </p>
              <form phx-submit="join_session" class="space-y-4">
                <input
                  type="text"
                  value={@session_code}
                  phx-keyup="update_code"
                  class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-purple-500 text-center uppercase font-mono"
                  placeholder="Enter Session Code"
                  maxlength="8"
                />
                <button
                  type="submit"
                  class="w-full bg-purple-600 text-white py-3 px-6 rounded-lg hover:bg-purple-700 transition font-medium"
                >
                  Join Session
                </button>
              </form>
            </div>
          </div>
        </div>

        <div class="mt-12 text-center text-white/80 text-sm">
          <p>
            Help presenters understand when you're following along or when you're lost.
            <br>
            Simple, real-time feedback for better presentations.
          </p>
        </div>
      </div>
    </div>
    """
  end
end