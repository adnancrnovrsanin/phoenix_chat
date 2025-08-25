WebRTC Video Conferencing PoC Specification for Phoenix v1.8

1) Goals and constraints

- Functional scope
  - Up to 6 participants per room using a peer-to-peer mesh topology
  - Guest join via display name; no authentication/SSO
  - Phoenix Channels for signaling
  - Phoenix LiveView UI for lobby and room
  - WebRTC features: mute/unmute microphone, toggle camera, screen share, participant list, in-room text chat, device selection (mic/camera)
  - Presence-driven participant roster and media state
  - Local development only
- Non-goals
  - No TURN relay, only STUN
  - No recording or persistence of chat/media
  - No production hardening or deployment
  - No server-side media mixing or SFU
- Constraints
  - 6-participant mesh: each participant holds up to N-1 RTCPeerConnections
    - Bandwidth scales approximately O(N^2) aggregate, O(N) per participant
    - CPU scales with number of active encodes/decodes and screen share streams
  - Google STUN only: stun:stun.l.google.com:19302
  - Phoenix v1.8 LiveView and components usage must follow project guidelines in [AGENTS.md](AGENTS.md)

2) High-level architecture

- Phoenix Endpoint and Socket
  - Endpoint handles HTTP and WebSocket upgrades; static assets for LiveView and Hooks
  - WebSocket transport for Channels and LiveView under the default endpoint
  - Files:
    - [lib/phoenix_chat_web/endpoint.ex](lib/phoenix_chat_web/endpoint.ex)
    - [lib/phoenix_chat_web.ex](lib/phoenix_chat_web.ex)
- Signaling over Channels
  - Room Channel per room topic: room:<room_id>
  - Validates join payloads, enforces capacity, routes signaling messages (offer/answer/ice), propagates media state and chat
  - Presence used for participant roster and media/device metadata
  - Files:
    - [lib/phoenix_chat_web/channels/room_channel.ex](lib/phoenix_chat_web/channels/room_channel.ex)
    - [lib/phoenix_chat_web/channels/presence.ex](lib/phoenix_chat_web/channels/presence.ex)
- LiveView UI
  - Lobby LiveView: display name and room entry/generation
    - [lib/phoenix_chat_web/live/lobby_live.ex](lib/phoenix_chat_web/live/lobby_live.ex)
    - [lib/phoenix_chat_web/live/lobby_live.html.heex](lib/phoenix_chat_web/live/lobby_live.html.heex)
  - Room LiveView: renders layout, controls, video grid, participant list, chat; wires a JS Hook for WebRTC logic
    - [lib/phoenix_chat_web/live/room_live.ex](lib/phoenix_chat_web/live/room_live.ex)
    - [lib/phoenix_chat_web/live/room_live.html.heex](lib/phoenix_chat_web/live/room_live.html.heex)
- Client hooks and assets
  - WebRTC room hook and client logic bundled in app JS
    - [assets/js/app.js](assets/js/app.js)
  - Styling for grid, controls, responsive layout
    - [assets/css/app.css](assets/css/app.css)
- Layouts
  - All LiveView templates begin with the Layouts.app wrapper
  - Files:
    - [lib/phoenix_chat_web/components/layouts.ex](lib/phoenix_chat_web/components/layouts.ex)
    - [lib/phoenix_chat_web/components/layouts/root.html.heex](lib/phoenix_chat_web/components/layouts/root.html.heex)

3) Routing and navigation

- Routes
  - / – Lobby: form for display name and room id; generate random room id
  - /r/:room_id – Room: LiveView that hosts the video call
- Router file and scope
  - Routes defined in [lib/phoenix_chat_web/router.ex](lib/phoenix_chat_web/router.ex) under default :browser scope using the scope aliasing provided by Phoenix v1.8

4) Signaling protocol (Channels)

- Transport and topic
  - Phoenix Channel topic: room:<room_id>
  - One channel instance per socket connected to a room
- Join parameters
  - Required: display_name (string, 1..64)
  - Optional: device_info (map)
    - audio_device_id (string)
    - video_device_id (string)
    - labels are not trusted; device IDs preferred
- Participant limit enforcement
  - On join, count presences in the room; if count >= 6, reject with "error:capacity"
- Participant identity
  - Server generates participant_id (UUIDv4) on join; returned in join reply and used as Presence key
- Events and payloads
  - Common fields for all messages
    - room_id: string
    - from_id: string (server populates from socket assigns where appropriate)
    - to_id: string (for directed messages)
    - ts: integer (server or client-supplied unix ms; server may overwrite/augment)
  - signal:offer (client -> server -> specific peer)
    - Direction: from caller to server; server validates and forwards to to_id
    - Payload
      - sdp: string (offer SDP)
      - to_id: string
  - signal:answer (client -> server -> specific peer)
    - Direction: from callee to server; server validates and forwards to to_id
    - Payload
      - sdp: string (answer SDP)
      - to_id: string
  - signal:ice (client -> server -> specific peer)
    - Direction: either side; server validates and forwards to to_id
    - Payload
      - candidate: string
      - sdpMid: string or null
      - sdpMLineIndex: integer or null
      - end_of_candidates: boolean (optional; when true indicates end)
      - to_id: string
  - presence_state / presence_diff
    - Standard Phoenix Presence messages broadcast by server
  - media:update (client -> server -> broadcast)
    - Direction: client announces state changes, server validates, updates Presence meta, and broadcasts to room
    - Payload
      - audio_muted: boolean (required)
      - video_enabled: boolean (required)
      - screensharing: boolean (required)
      - device_info: map (optional, sanitized)
  - chat:msg (client -> server -> broadcast)
    - Direction: client sends text, server sanitizes and broadcasts
    - Payload
      - text: string (1..500)
- Message payload schema examples (JSON-like)
  - Join reply
    - { ok: true, self_id: <participant_id>, room_id: <room_id>, presence: <presence_state> }
  - signal:offer
    - { room_id, from_id, to_id, sdp, ts }
  - signal:answer
    - { room_id, from_id, to_id, sdp, ts }
  - signal:ice
    - { room_id, from_id, to_id, candidate, sdpMid, sdpMLineIndex, end_of_candidates, ts }
  - media:update
    - { room_id, from_id, audio_muted, video_enabled, screensharing, device_info, ts }
  - chat:msg
    - { room_id, from_id, display_name, text, ts }
- Error handling and push formats
  - error:capacity
    - { error: capacity, room_id, limit: 6 }
  - error:invalid_payload
    - { error: invalid_payload, event: <event>, reasons: [..] }
  - error:unknown_peer
    - { error: unknown_peer, to_id }
  - error:not_in_room
    - { error: not_in_room }
  - Client behavior
    - On error:capacity, redirect back to Lobby with a notice
    - On error:invalid_payload, drop the operation and show a toast
    - On error:unknown_peer, evict any local peer connection to to_id
- Validation guidance (server)
  - Ensure room_id inferred from topic matches payload room_id if provided
  - Validate required keys and types; reject unexpected keys by Map.take / pattern matching
  - Size limits: sdp <= 1 MB; candidate <= 2 KB; text <= 500 chars
  - Sanitize chat text using Phoenix.HTML.html_escape then safe_to_string

5) Presence model

- Presence module and usage
  - [lib/phoenix_chat_web/channels/presence.ex](lib/phoenix_chat_web/channels/presence.ex) to define Presence with pubsub server
- Presence key
  - participant_id (UUIDv4), generated server-side on join and assigned to socket
- Presence metadata fields
  - display_name: string
  - audio_muted: boolean
  - video_enabled: boolean
  - screensharing: boolean
  - device_info: map
    - audio_device_id: string
    - video_device_id: string
- Lifecycle
  - On join:
    - Enforce capacity and params
    - Track presence with initial metadata
    - Push presence_state to the joining client
  - On leave:
    - Presence automatically pruned; other clients receive presence_diff
- Consumption in Room LiveView
  - Subscribe Room LiveView to Presence topic for the room on mount
  - Maintain participant list assign; update on presence_diff for roster and media states

6) Client-side WebRTC design (mesh)

- Topology
  - Full mesh: each participant maintains a RTCPeerConnection per other participant
  - Map of peer connections keyed by remote participant_id
- STUN config
  - iceServers: [{ urls: stun:stun.l.google.com:19302 }]
- Media tracks
  - Primary local MediaStream from getUserMedia with audio/video
  - Toggling:
    - Toggle mic by enabling/disabling audio track
    - Toggle camera by enabling/disabling video track; renegotiate if track added/removed
  - Screen share
    - Optional display MediaStream via getDisplayMedia; add as track or replace sender
    - Renegotiate on start/stop; update media:update and Presence meta
- Negotiation rules
  - Offerer selection: compare local self_id and remote participant_id lexicographically; the lexically smaller id initiates offer
  - On new remote presence:
    - If local self_id < remote_id: create RTCPeerConnection, add tracks, create and send offer
    - Else: await offer then answer
  - Renegotiation triggers:
    - Start/stop screen share
    - Camera track availability changes (e.g., device switch or stop)
    - Transceiver or sender replaceTrack operations
- ICE handling
  - Use trickle ICE; forward candidates via signal:ice as they are gathered
  - Add ICE candidates to the corresponding peer connection as they arrive
  - End-of-candidates indicated by either null candidate from browser or end_of_candidates flag
- Device selection and state
  - Enumerate devices on mount and on devicechange
  - Store selected audio_device_id and video_device_id locally and in device_info presence meta via media:update
  - On selection change:
    - Obtain a new MediaStream with exact deviceId constraints
    - Replace the corresponding RTCRtpSender track; renegotiate if necessary
- Error paths and fallbacks
  - getUserMedia denial:
    - Enter audio_muted=true and/or video_enabled=false state; still allow join and chat
  - getDisplayMedia denial:
    - Do not enter screensharing; keep previous state
  - Peer connection failures:
    - Close and recreate RTCPeerConnection; request re-offer from other side by sending a no-op media:update to trigger renegotiation

7) LiveView UI and UX

- Lobby UI in [lib/phoenix_chat_web/live/lobby_live.html.heex](lib/phoenix_chat_web/live/lobby_live.html.heex)
  - Use the app’s core input component for fields
    - Inputs: display_name, room_id
  - Button: Generate random room id
  - On submit: navigate to /r/:room_id with params
- Room UI in [lib/phoenix_chat_web/live/room_live.html.heex](lib/phoenix_chat_web/live/room_live.html.heex)
  - Must start with <Layouts.app flash={@flash} current_scope={@current_scope}> wrapper per guidelines
  - Containers and IDs
    - #video-grid: grid container for remote and local video elements; phx-update=stream
    - #local-video: muted, autoplay local preview
    - #controls-bar: control buttons container
    - #participants-panel: presence-driven list of participants and media states
    - #chat-panel: messages stream container
    - #chat-form: message input form using the core input component
    - #message-list: stream target for chat messages
  - Controls
    - Mute/unmute mic
    - Toggle camera
    - Start/stop screen share
    - Device selectors for mic and camera
  - Hook wiring
    - Root container carries phx-hook=WebRTCRoom
    - Data attributes include room_id and display_name
- Styling targets in [assets/css/app.css](assets/css/app.css)
  - Grid layout for #video-grid with responsive columns
  - Control bar layout and button states
  - Panels responsive behavior for participants and chat

8) Security and privacy

- No authentication; display names are unverified; treat as untrusted input
- Sanitize chat messages server-side
  - Use Phoenix.HTML.html_escape followed by safe_to_string before broadcast
- Payload validation
  - Enforce size limits; drop unexpected keys via Map.take
  - Validate field presence and types at channel handlers
- Topic joining restrictions
  - Reject joins where room_id param is missing or does not match topic suffix
- Privacy
  - No recording or persistence of media or chat; in-memory only
  - Do not expose device labels without user gesture; rely on device IDs when available

9) Telemetry and logging

- Channel logging in [lib/phoenix_chat_web/channels/room_channel.ex](lib/phoenix_chat_web/channels/room_channel.ex)
  - Log at info or debug:
    - join/leave events and capacity rejections
    - signal:offer, signal:answer, signal:ice routing decisions
    - media:update validations and broadcasts
    - chat:msg receipt and sanitization outcome
  - Suggested metadata:
    - room_id, from_id, to_id, event, presences_count, bytes_estimate(optional), ts
- LiveView logging in [lib/phoenix_chat_web/live/room_live.ex](lib/phoenix_chat_web/live/room_live.ex)
  - Log presence_diff handling summaries: joins/leaves count deltas
  - Log hook initialization and teardown

10) Testing strategy

- LiveView tests under [test/phoenix_chat_web](test/phoenix_chat_web)
  - Lobby renders form elements with correct IDs
  - Room renders containers (#video-grid, #controls-bar, #participants-panel, #chat-panel, #chat-form)
  - Use Phoenix.LiveViewTest element/2, has_element?/2 with the IDs/classes defined
- Channel tests
  - Join capacity limit enforcement at exactly 6 participants
  - Event validation and forwarding:
    - signal:offer, signal:answer, signal:ice directed routing
  - media:update and chat:msg:
    - Validate acceptance/rejection paths, meta updates, and sanitization
- Presence tests
  - On join, presence meta contains required fields
  - presence_diff propagates on leave
- Notes
  - Avoid asserting against raw HTML; use selectors and element/2 helpers
  - Use isolated, small test files for each major behavior

11) Local development and constraints

- Browser permissions
  - getUserMedia and getDisplayMedia require user consent; test via localhost to avoid HTTPS requirement
- Network connectivity
  - STUN only; connectivity may fail under symmetric NATs; acceptable for PoC
- Future extensions
  - Add TURN for reliability
  - Add auth and moderation
  - Consider SFU for scalability beyond 4–6 participants

12) Implementation checklist mapping

- Endpoint/socket wiring
  - [lib/phoenix_chat_web/endpoint.ex](lib/phoenix_chat_web/endpoint.ex)
  - [lib/phoenix_chat_web.ex](lib/phoenix_chat_web.ex)
- Channel and Presence
  - [lib/phoenix_chat_web/channels/room_channel.ex](lib/phoenix_chat_web/channels/room_channel.ex)
  - [lib/phoenix_chat_web/channels/presence.ex](lib/phoenix_chat_web/channels/presence.ex)
- LiveViews and templates
  - [lib/phoenix_chat_web/live/lobby_live.ex](lib/phoenix_chat_web/live/lobby_live.ex)
  - [lib/phoenix_chat_web/live/lobby_live.html.heex](lib/phoenix_chat_web/live/lobby_live.html.heex)
  - [lib/phoenix_chat_web/live/room_live.ex](lib/phoenix_chat_web/live/room_live.ex)
  - [lib/phoenix_chat_web/live/room_live.html.heex](lib/phoenix_chat_web/live/room_live.html.heex)
- JS hook
  - [assets/js/app.js](assets/js/app.js)
- Styles
  - [assets/css/app.css](assets/css/app.css)
- Tests
  - [test/phoenix_chat_web](test/phoenix_chat_web)

Appendix A: Channel handler behaviors (prose)

- Join
  - Verify room_id in topic and params; validate display_name; enforce capacity using Presence.list
  - Assign participant_id = UUIDv4; push presence_state; track presence with initial meta
  - Reply with ok and self_id
- handle_in events
  - signal:offer, signal:answer
    - Validate payload keys and size; ensure to_id is present in Presence; broadcast to specific to_id via push to that socket
  - signal:ice
    - Validate candidate structure; forward to to_id if known; else reply error:unknown_peer
  - media:update
    - Validate booleans; sanitize device_info by allowing only device ids; update Presence meta; broadcast updated media state
  - chat:msg
    - Validate length; html_escape text; include display_name from Presence meta; broadcast to room

Appendix B: LiveView and Hook contract

- Room LiveView assigns
  - :room_id, :display_name, :self_id, :participants (from Presence), :messages stream
- DOM contracts
  - #video-grid uses phx-update=stream and child items keyed by presence ids
  - #local-video has muted autoplay and contains local stream
  - Buttons in #controls-bar have stable IDs:
    - #btn-mic, #btn-camera, #btn-screenshare
  - Selects:
    - #sel-mic, #sel-camera
- Hook responsibilities in [assets/js/app.js](assets/js/app.js)
  - On mounted:
    - Connect to Channel room:<room_id> with display_name and optional device_info
    - Capture local media; render to #local-video; publish initial media:update
    - Initialize maps: peers, senders, streams
    - Subscribe to channel events; subscribe to presence_state/diff via channel on callbacks
  - On destroyed:
    - Close all RTCPeerConnections and tracks; leave channel

Appendix C: Minimal signaling flow

- Sequence overview for a new peer joining a room

```mermaid
sequenceDiagram
  participant A as Client A
  participant S as Phoenix Room Channel
  participant B as Client B

  A->>S: join room:1 display_name
  S->>A: ok self_id presence_state
  S->>B: presence_diff join of A

  alt A self_id < B id
    A->>S: signal:offer {to_id: B, sdp}
    S->>B: signal:offer {from_id: A, sdp}
    B->>S: signal:answer {to_id: A, sdp}
    S->>A: signal:answer {from_id: B, sdp}
  else
    B initiates offer
  end

  A->>S: signal:ice {to_id: B, candidate}
  S->>B: signal:ice {from_id: A, candidate}
  B->>S: signal:ice {to_id: A, candidate}
  S->>A: signal:ice {from_id: B, candidate}
```

Notes and compliance

- Follow Phoenix v1.8 rules:
  - LiveView templates begin with Layouts.app wrapper from [lib/phoenix_chat_web/components/layouts.ex](lib/phoenix_chat_web/components/layouts.ex) and [lib/phoenix_chat_web/components/layouts/root.html.heex](lib/phoenix_chat_web/components/layouts/root.html.heex)
  - Use imported .input component from [lib/phoenix_chat_web/components/core_components.ex](lib/phoenix_chat_web/components/core_components.ex) for form inputs
  - Use <.link navigate> or push_navigate for navigation in LiveView templates and modules
  - Do not call <.flash_group> outside layouts.ex
- HTTP client note from project guidelines
  - If any HTTP calls are ever needed, use Req; however, this PoC does not require external HTTP calls