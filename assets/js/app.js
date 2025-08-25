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
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/phoenix_chat"
import topbar from "../vendor/topbar"

const Hooks = {
  ...colocatedHooks,

  RoomRTC: {
    mounted() {
      this.log = (...args) => console.log("[RoomRTC]", ...args)

      // Read dataset
      this.roomId = this.el.dataset.roomId || this.el.getAttribute("data-room-id")
      this.displayName = this.el.dataset.displayName || this.el.getAttribute("data-display-name")

      // Cache DOM controls
      this.btnMic = document.getElementById("btn-mic")
      this.btnCam = document.getElementById("btn-cam")
      this.btnShare = document.getElementById("btn-share")
      this.selMic = document.getElementById("sel-mic")
      this.selCam = document.getElementById("sel-cam")
      this.screenVideo = document.getElementById("screen-video")

      // Wire control listeners
      if (this.btnMic) {
        this.btnMic.onclick = () => {
          const t = this.getTrack("audio")
          if (!t) { this.log("No audio track to toggle mic"); return }
          t.enabled = !t.enabled
          this.updateButtonStates()
          this.pushMediaUpdate({ audio_muted: !t.enabled })
        }
      }
      if (this.btnCam) {
        this.btnCam.onclick = () => {
          const t = this.getTrack("video")
          if (!t) { this.log("No video track to toggle camera"); return }
          t.enabled = !t.enabled
          this.updateButtonStates()
          this.pushMediaUpdate({ video_enabled: t.enabled })
        }
      }
      if (this.selMic) {
        this.selMic.onchange = async (e) => {
          await this.switchDevice("audioinput", e.target.value)
        }
      }
      if (this.selCam) {
        this.selCam.onchange = async (e) => {
          await this.switchDevice("videoinput", e.target.value)
        }
      }
      if (this.btnShare) {
        this.btnShare.onclick = async () => {
          try {
            if (!this.screenStream) {
              await this.startScreenShare()
            } else {
              await this.stopScreenShare()
            }
          } catch (e) {
            this.log("btnShare click error", e)
          }
        }
      }

      // Guard basic requirements
      if (!this.roomId || !this.displayName) {
        this.log("Missing roomId/displayName, aborting hook init", { roomId: this.roomId, displayName: this.displayName })
        return
      }

      // State
      this.maxPeers = 5 // defensive client-side cap (server caps total participants at 6)
      this.peers = new Map()
      this.remoteStreams = new Map()
      this.localStream = null
      this.localStreamReady = Promise.resolve() // will be replaced after channel join OK
      this.pendingPresenceState = null
      this.pendingJoins = []
      // Screen share state
      this.screenStream = null
      this.cameraTrack = null

      // Phoenix Channel socket for signaling
      this.phxSocket = new Socket("/socket")
      this.phxSocket.connect()

      this.channel = this.phxSocket.channel(`room:${this.roomId}`, {
        display_name: this.displayName,
        device_info: {}
      })

      this.registerChannelHandlers()

      this.channel
        .join()
        .receive("ok", async (resp) => {
          this.selfId = resp.participant_id
          this.log("Joined room channel", { selfId: this.selfId })

          // Start local media after we have selfId
          this.localStreamReady = this.startLocalMedia()
          try {
            await this.localStreamReady
            // Cache initial camera track (if available)
            this.cameraTrack = this.getTrack("video") || null
            await this.populateDevices()
            this.updateButtonStates()
            this.pushMediaUpdate({})
          } catch (_) {}

          // If presence_state arrived before join ok, process it now
          if (this.pendingPresenceState) {
            this.handlePresenceState(this.pendingPresenceState)
            this.pendingPresenceState = null
          }

          // If presence_diff joins arrived before join ok, process now
          if (this.pendingJoins.length > 0) {
            for (const rid of this.pendingJoins) {
              if (rid !== this.selfId) {
                const initiator = this.selfId < rid
                void this.ensurePeer(rid, initiator)
              }
            }
            this.pendingJoins = []
          }
        })
        .receive("error", (err) => this.log("Channel join error", err))
    },

    destroyed() {
      try {
        // Remove event listeners from controls
        if (this.btnMic) this.btnMic.onclick = null
        if (this.btnCam) this.btnCam.onclick = null
        if (this.btnShare) this.btnShare.onclick = null
        if (this.selMic) this.selMic.onchange = null
        if (this.selCam) this.selCam.onchange = null
      } catch (_) {}

      try {
        if (this.channel) {
          this.channel.leave()
        }
      } catch (_) {}

      try {
        if (this.phxSocket) {
          this.phxSocket.disconnect()
        }
      } catch (_) {}

      // Stop screen share stream and reset UI if active
      try {
        if (this.screenStream) {
          this.screenStream.getTracks().forEach(t => {
            try { t.stop() } catch (_) {}
          })
          this.screenStream = null
        }
        if (this.screenVideo) {
          this.screenVideo.srcObject = null
          if (this.screenVideo.classList) this.screenVideo.classList.add("hidden")
        }
        if (this.btnShare) {
          this.btnShare.textContent = "Share Screen"
        }
      } catch (_) {}

      try {
        // Close all peers
        this.peers && this.peers.forEach((pc) => {
          try { pc.close() } catch (_) {}
        })
        this.peers && this.peers.clear()

        // Stop local media
        if (this.localStream) {
          this.localStream.getTracks().forEach(t => {
            try { t.stop() } catch (_) {}
          })
        }

        // Remove remote video elements
        const grid = this.getVideoGrid()
        if (grid) {
          grid.querySelectorAll('video[id^="remote-"]').forEach(v => v.remove())
        }
      } catch (e) {
        this.log("Error during cleanup", e)
      }
    },

    // --- Helpers / Methods ---

    registerChannelHandlers() {
      // Presence full state
      this.channel.on("presence_state", (state) => {
        if (!this.selfId) {
          // Buffer until join ok provides selfId
          this.pendingPresenceState = state
          return
        }
        this.handlePresenceState(state)
      })

      // Presence diffs (joins/leaves)
      this.channel.on("presence_diff", (diff) => {
        if (!this.selfId) {
          const joinIds = Object.keys(diff?.joins || {})
          this.pendingJoins.push(...joinIds)
          return
        }
        this.handlePresenceDiff(diff)
      })

      // Signaling: Offer
      this.channel.on("signal:offer", async (payload) => {
        try {
          if (!this.selfId || payload?.to_id !== this.selfId) return
          const fromId = payload.from_id
          const pc = await this.ensurePeer(fromId, false)
          if (!pc) return

          await pc.setRemoteDescription({ type: "offer", sdp: payload.sdp })
          const answer = await pc.createAnswer()
          await pc.setLocalDescription(answer)

          this.channel.push("signal:answer", {
            to_id: fromId,
            sdp: pc.localDescription?.sdp
          })
        } catch (e) {
          this.log("Error handling signal:offer", e)
        }
      })

      // Signaling: Answer
      this.channel.on("signal:answer", async (payload) => {
        try {
          if (!this.selfId || payload?.to_id !== this.selfId) return
          const fromId = payload.from_id
          const pc = this.peers.get(fromId)
          if (!pc) {
            this.log("Answer for unknown peer", fromId)
            return
          }
          await pc.setRemoteDescription({ type: "answer", sdp: payload.sdp })
        } catch (e) {
          this.log("Error handling signal:answer", e)
        }
      })

      // Signaling: ICE
      this.channel.on("signal:ice", async (payload) => {
        try {
          if (!this.selfId || payload?.to_id !== this.selfId) return
          const fromId = payload.from_id
          const pc = this.peers.get(fromId)
          if (!pc) return

          const { candidate, sdpMid, sdpMLineIndex } = payload
          if (!candidate) return

          await pc.addIceCandidate({ candidate, sdpMid, sdpMLineIndex })
        } catch (e) {
          this.log("Error handling signal:ice", e)
        }
      })
    },

    handlePresenceState(state) {
      try {
        const ids = Object.keys(state || {})
        for (const rid of ids) {
          if (rid === this.selfId) continue
          const initiator = this.selfId < rid
          void this.ensurePeer(rid, initiator)
        }
      } catch (e) {
        this.log("handlePresenceState error", e)
      }
    },

    handlePresenceDiff(diff) {
      try {
        const joins = Object.keys(diff?.joins || {})
        for (const rid of joins) {
          if (rid === this.selfId) continue
          const initiator = this.selfId < rid
          void this.ensurePeer(rid, initiator)
        }

        const leaves = Object.keys(diff?.leaves || {})
        for (const rid of leaves) {
          this.teardownPeer(rid)
        }
      } catch (e) {
        this.log("handlePresenceDiff error", e)
      }
    },

    async startLocalMedia() {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true })
        this.localStream = stream

        // Attach to local video element
        const localVideo = this.ensureLocalVideoElement()
        if (localVideo) {
          localVideo.muted = true
          localVideo.autoplay = true
          localVideo.playsInline = true
          localVideo.srcObject = stream
        }

        // Add tracks to any existing peers
        this.peers.forEach((pc) => {
          stream.getTracks().forEach(t => pc.addTrack(t, stream))
        })

        this.log("Local media started")
      } catch (e) {
        this.log("getUserMedia failed", e)
      }
    },

    async ensurePeer(remoteId, initiator = false) {
      if (!remoteId) return null
      if (this.peers.has(remoteId)) return this.peers.get(remoteId)

      if (this.peers.size >= this.maxPeers) {
        this.log("Peer cap reached, skipping new peer", { remoteId, size: this.peers.size })
        return null
      }

      const pc = new RTCPeerConnection({
        iceServers: [{ urls: "stun:stun.l.google.com:19302" }]
      })

      // Store before any async to avoid races
      this.peers.set(remoteId, pc)

      // Wire ICE
      pc.onicecandidate = (e) => {
        const c = e.candidate
        if (c) {
          this.channel.push("signal:ice", {
            to_id: remoteId,
            candidate: c.candidate,
            sdpMid: c.sdpMid,
            sdpMLineIndex: c.sdpMLineIndex
          })
        }
      }

      // Remote track handler
      pc.ontrack = (e) => {
        try {
          let stream = e.streams && e.streams[0]
          if (!stream) {
            // Fallback if streams array is empty
            stream = new MediaStream([e.track])
          }
          this.remoteStreams.set(remoteId, stream)

          const video = this.getOrCreateRemoteVideo(remoteId)
          if (video && video.srcObject !== stream) {
            video.autoplay = true
            video.playsInline = true
            video.srcObject = stream
          }
        } catch (err) {
          this.log("ontrack error", err)
        }
      }

      // Add local tracks once ready
      try {
        await this.localStreamReady
        if (this.localStream) {
          this.localStream.getTracks().forEach(t => pc.addTrack(t, this.localStream))
        }
        // If we are currently screen sharing, replace the video sender with the screen track for this new peer
        if (this.screenStream) {
          const screenTrack = this.screenStream.getVideoTracks()[0] || null
          if (screenTrack) {
            try {
              const sender = pc.getSenders().find(s => s.track && s.track.kind === "video")
              if (sender) await sender.replaceTrack(screenTrack)
            } catch (e) {
              this.log("ensurePeer replaceTrack(screen) error", e)
            }
          }
        }
      } catch (_) {}

      // Initiate offer if we are the initiator
      if (initiator) {
        try {
          const offer = await pc.createOffer()
          await pc.setLocalDescription(offer)
          this.channel.push("signal:offer", {
            to_id: remoteId,
            sdp: pc.localDescription?.sdp
          })
        } catch (e) {
          this.log("Error creating/sending offer", e)
        }
      }

      return pc
    },

    teardownPeer(remoteId) {
      try {
        const pc = this.peers.get(remoteId)
        if (pc) {
          try { pc.close() } catch (_) {}
          this.peers.delete(remoteId)
        }
        this.remoteStreams.delete(remoteId)

        const el = document.getElementById(`remote-${remoteId}`)
        if (el && el.parentNode) el.parentNode.removeChild(el)
      } catch (e) {
        this.log("teardownPeer error", e)
      }
    },

    getVideoGrid() {
      return document.getElementById("video-grid")
    },

    ensureLocalVideoElement() {
      let el = document.getElementById("local-video")
      if (!el) {
        const grid = this.getVideoGrid()
        el = document.createElement("video")
        el.id = "local-video"
        el.muted = true
        el.autoplay = true
        el.playsInline = true
        if (grid) grid.appendChild(el)
      }
      return el
    },

    getOrCreateRemoteVideo(remoteId) {
      const id = `remote-${remoteId}`
      let el = document.getElementById(id)
      if (!el) {
        const grid = this.getVideoGrid()
        el = document.createElement("video")
        el.id = id
        el.autoplay = true
        el.playsInline = true
        if (grid) grid.appendChild(el)
      }
      return el
    },

    // --- Media controls / devices ---

    async enumerate() {
      try {
        return await navigator.mediaDevices.enumerateDevices()
      } catch (e) {
        console.warn("[RoomRTC] enumerateDevices failed", e)
        return []
      }
    },

    async populateDevices() {
      try {
        const devices = await this.enumerate()
        const mics = devices.filter(d => d.kind === "audioinput")
        const cams = devices.filter(d => d.kind === "videoinput")

        const setOptions = (sel, list, kind) => {
          if (!sel) return
          const prev = sel.value
          sel.innerHTML = ""

          list.forEach((d, idx) => {
            const opt = document.createElement("option")
            opt.value = d.deviceId || ""
            opt.textContent = d.label || (kind === "audioinput" ? `Microphone ${idx + 1}` : `Camera ${idx + 1}`)
            sel.appendChild(opt)
          })

          let target = (prev && list.find(d => d.deviceId === prev)?.deviceId) || null
          if (!target) {
            const curTrack = this.getTrack(kind === "audioinput" ? "audio" : "video")
            const curId = curTrack && (curTrack.getSettings?.().deviceId || null)
            if (curId && list.find(d => d.deviceId === curId)) {
              target = curId
            }
          }
          if (!target && list[0]) target = list[0].deviceId
          if (target) sel.value = target
        }

        setOptions(this.selMic, mics, "audioinput")
        setOptions(this.selCam, cams, "videoinput")
      } catch (e) {
        console.warn("[RoomRTC] populateDevices error", e)
      }
    },

    getTrack(kind) {
      if (!this.localStream) return null
      if (kind === "audio" || kind === "audioinput") {
        return this.localStream.getAudioTracks()[0] || null
      }
      if (kind === "video" || kind === "videoinput") {
        return this.localStream.getVideoTracks()[0] || null
      }
      return null
    },

    updateButtonStates() {
      try {
        if (this.btnMic) {
          const at = this.getTrack("audio")
          const enabled = at ? !!at.enabled : true
          this.btnMic.textContent = enabled ? "Mic On" : "Mic Off"
          this.btnMic.setAttribute("aria-pressed", (!enabled).toString())
        }
        if (this.btnCam) {
          const vt = this.getTrack("video")
          const enabled = vt ? !!vt.enabled : false
          this.btnCam.textContent = enabled ? "Camera On" : "Camera Off"
          this.btnCam.setAttribute("aria-pressed", enabled.toString())
        }
      } catch (_) {}
    },

    pushMediaUpdate(partial) {
      try {
        const at = this.getTrack("audio")
        const vt = this.getTrack("video")
        const payload = Object.assign({
          audio_muted: !(at ? at.enabled : true),
          video_enabled: vt ? !!vt.enabled : false,
          device_info: {
            audioinput: this.selMic && this.selMic.value ? this.selMic.value : null,
            videoinput: this.selCam && this.selCam.value ? this.selCam.value : null
          }
        }, partial || {})

        if (this.channel) {
          this.channel.push("media:update", payload)
        }
      } catch (e) {
        this.log("pushMediaUpdate error", e)
      }
    },

    async switchDevice(kind, deviceId) {
      try {
        if (!deviceId) return
        const isAudio = kind === "audioinput"

        // Request only the needed kind to avoid unnecessary prompts
        const constraints = isAudio
          ? { audio: { deviceId: { exact: deviceId } }, video: false }
          : { audio: false, video: { deviceId: { exact: deviceId } } }

        const newStream = await navigator.mediaDevices.getUserMedia(constraints)
        const newTrack = isAudio ? (newStream.getAudioTracks()[0] || null) : (newStream.getVideoTracks()[0] || null)
        if (!newTrack) {
          this.log("No new track from getUserMedia for kind", kind)
          return
        }

        const oldTrack = this.getTrack(isAudio ? "audio" : "video")

        // Replace sender tracks across all peers (no renegotiation)
        this.peers && this.peers.forEach((pc) => {
          try {
            const sender = pc.getSenders().find(s => s.track && s.track.kind === newTrack.kind)
            if (sender) sender.replaceTrack(newTrack)
          } catch (e) {
            this.log("replaceTrack error", e)
          }
        })

        // Update local stream
        if (this.localStream) {
          if (oldTrack) {
            try { oldTrack.stop() } catch (_) {}
            try { this.localStream.removeTrack(oldTrack) } catch (_) {}
          }
          this.localStream.addTrack(newTrack)
        }

        // Update local preview after video switch
        if (!isAudio) {
          const localVideo = this.ensureLocalVideoElement()
          if (localVideo) {
            localVideo.srcObject = this.localStream
          }
        }

        await this.populateDevices()
        this.updateButtonStates()
        this.pushMediaUpdate({})
      } catch (e) {
        console.warn("[RoomRTC] switchDevice error", e)
      }
    },

    async startScreenShare() {
      try {
        if (this.screenStream) return

        const screen = await navigator.mediaDevices.getDisplayMedia({
          video: { frameRate: 15 },
          audio: false
        })

        this.screenStream = screen
        const screenTrack = screen.getVideoTracks()[0] || null
        if (!screenTrack) {
          this.log("No screen video track from getDisplayMedia")
          try { screen.getTracks().forEach(t => { try { t.stop() } catch (_) {} }) } catch (_) {}
          this.screenStream = null
          return
        }

        // Cache camera track if not already cached
        if (!this.cameraTrack) {
          this.cameraTrack = this.getTrack("video") || null
        }

        // Stop share if user ends the screen picker
        screenTrack.onended = () => { void this.stopScreenShare() }

        // Replace outgoing video sender track across all peers
        for (const [remoteId, pc] of this.peers.entries()) {
          try {
            const sender = pc.getSenders().find(s => s.track && s.track.kind === "video")
            if (sender) await sender.replaceTrack(screenTrack)
          } catch (e) {
            this.log("replaceTrack(screen) error", { remoteId, e })
          }
        }

        // Local preview
        if (this.screenVideo) {
          if (this.screenVideo.classList) this.screenVideo.classList.remove("hidden")
          this.screenVideo.muted = true
          this.screenVideo.autoplay = true
          this.screenVideo.playsInline = true
          this.screenVideo.srcObject = this.screenStream
        }

        // Presence update
        this.pushMediaUpdate({ screensharing: true })

        // Renegotiate offers for robustness
        for (const [remoteId, pc] of this.peers.entries()) {
          try {
            const offer = await pc.createOffer()
            await pc.setLocalDescription(offer)
            this.channel.push("signal:offer", { to_id: remoteId, sdp: pc.localDescription?.sdp })
          } catch (e) {
            this.log("renegotiate offer (screen) error", { remoteId, e })
          }
        }

        if (this.btnShare) this.btnShare.textContent = "Stop Share"
      } catch (e) {
        this.log("startScreenShare error", e)
      }
    },

    async stopScreenShare() {
      try {
        if (!this.screenStream) return

        const cameraTrack = this.cameraTrack || this.getTrack("video") || null

        // Replace back to camera if available
        if (cameraTrack) {
          for (const [remoteId, pc] of this.peers.entries()) {
            try {
              const sender = pc.getSenders().find(s => s.track && s.track.kind === "video")
              if (sender) await sender.replaceTrack(cameraTrack)
            } catch (e) {
              this.log("replaceTrack(camera) error", { remoteId, e })
            }
          }
        }

        // Stop and clear screen stream
        try { this.screenStream.getTracks().forEach(t => { try { t.stop() } catch (_) {} }) } catch (_) {}
        this.screenStream = null

        // Hide preview
        if (this.screenVideo) {
          this.screenVideo.srcObject = null
          if (this.screenVideo.classList) this.screenVideo.classList.add("hidden")
        }

        // Presence update
        this.pushMediaUpdate({ screensharing: false })

        // Renegotiate back to camera
        for (const [remoteId, pc] of this.peers.entries()) {
          try {
            const offer = await pc.createOffer()
            await pc.setLocalDescription(offer)
            this.channel.push("signal:offer", { to_id: remoteId, sdp: pc.localDescription?.sdp })
          } catch (e) {
            this.log("renegotiate offer (camera) error", { remoteId, e })
          }
        }

        if (this.btnShare) this.btnShare.textContent = "Share Screen"
      } catch (e) {
        this.log("stopScreenShare error", e)
      }
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

