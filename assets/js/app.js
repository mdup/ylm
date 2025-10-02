// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/ylm";
import topbar from "../vendor/topbar";

// Ticker hook - queue-based character scrolling
//
// Concept: The ticker is a fixed-width character buffer.
// Each tick:
//   1. Shift all characters left by 1 (leftmost char drops off)
//   2. Get next character from message queue and append to right
//   3. If no message, append a space
//
// Message queue: Array of strings waiting to be displayed
// Current message: String being popped character by character
// Spacing: After each message, add N spaces before next message
//
const TickerHook = {
  mounted() {
    // The ticker buffer (fixed width, filled with spaces initially)
    this.charWidth = 16; // Pixels per character (monospace)
    this.viewportWidth = Math.floor(this.el.offsetWidth / this.charWidth);
    this.nbsp = "\u00A0"; // Non-breaking space (won't be collapsed by DOM)
    this.buffer = new Array(this.viewportWidth).fill(this.nbsp);

    // Message queue management
    this.messageQueue = []; // Messages waiting to be displayed
    this.currentMessage = null; // Current message being displayed (string)
    this.seenMessageIds = new Set();
    this.spacesRemaining = 0; // Spaces to add after current message
    this.maxChars = 128;

    this.spacingBetweenMessages = 4; // Characters of spacing between messages

    // Start the ticker with dynamic speed
    this.tickInterval = setInterval(() => this.tick(), this.getTickSpeed());

    console.log(`Ticker mounted: buffer width = ${this.viewportWidth} chars`);
  },

  getTickSpeed() {
    // Calculate remaining characters in queue
    const remainingChars = this.getRemainingChars();

    // Piecewise constant speed based on queue size
    if (remainingChars < 50) {
      return 150; // Slow and readable
    } else if (remainingChars < 100) {
      return 70; // Medium speed
    } else if (remainingChars < 200) {
      return 48; // Medium speed
    } else if (remainingChars < 300) {
      return 35; // Fast
    } else if (remainingChars < 400) {
      return 20; // Faster
    } else if (remainingChars < 600) {
      return 12; // Faster
    } else {
      return 6; // Very fast - catch up mode
    }
  },

  getRemainingChars() {
    let total = 0;

    // Count characters in current message
    if (this.currentMessage) {
      total += this.currentMessage.length;
    }

    // Count spacing remaining
    total += this.spacesRemaining;

    // Count all queued messages
    for (const msg of this.messageQueue) {
      total += msg.length + this.spacingBetweenMessages;
    }

    return total;
  },

  updated() {
    // Get new messages from LiveView
    const newMessages = this.el.dataset.messages
      ? JSON.parse(this.el.dataset.messages)
      : [];

    // Add unseen messages to the queue
    newMessages.forEach((msg) => {
      if (!this.seenMessageIds.has(msg.id)) {
        this.seenMessageIds.add(msg.id);
        // Format message and replace all regular spaces with non-breaking spaces
        const text = `"${msg.content.slice(0, this.maxChars)}" -- ${msg.participant_name}`;
        const textWithNbsp = text.replace(/ /g, this.nbsp);
        this.messageQueue.push(textWithNbsp);
        console.log(
          `Message queued: "${text}" (queue length: ${this.messageQueue.length})`,
        );
      }
    });
  },

  tick() {
    // 1. Shift buffer left (drop first character)
    this.buffer.shift();

    // 2. Get next character to append
    let nextChar = this.nbsp; // Default: non-breaking space

    if (this.spacesRemaining > 0) {
      // We're in spacing mode between messages
      nextChar = this.nbsp;
      this.spacesRemaining--;
    } else if (this.currentMessage && this.currentMessage.length > 0) {
      // Pop next character from current message
      nextChar = this.currentMessage[0];
      this.currentMessage = this.currentMessage.slice(1);

      // If message is now empty, start spacing
      if (this.currentMessage.length === 0) {
        this.currentMessage = null;
        this.spacesRemaining = this.spacingBetweenMessages;
      }
    } else if (this.messageQueue.length > 0) {
      // No current message, but we have queued messages
      this.currentMessage = this.messageQueue.shift();
      console.log(`Now displaying: "${this.currentMessage}"`);

      // Pop first character immediately
      nextChar = this.currentMessage[0];
      this.currentMessage = this.currentMessage.slice(1);

      if (this.currentMessage.length === 0) {
        this.currentMessage = null;
        this.spacesRemaining = this.spacingBetweenMessages;
      }
    }

    // 3. Append next character to buffer
    this.buffer.push(nextChar);

    // 4. Render buffer to DOM
    this.el.textContent = this.buffer.join("");

    // 5. Adjust tick speed based on queue size
    clearInterval(this.tickInterval);
    this.tickInterval = setInterval(() => this.tick(), this.getTickSpeed());
  },

  destroyed() {
    if (this.tickInterval) {
      clearInterval(this.tickInterval);
    }
  },
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...colocatedHooks, TickerHook },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
