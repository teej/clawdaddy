# Crawdaddy: Audio-First Agent Harness

## Project Spec v0.1

---

## What This Is

An audio-first agent interface inspired by Jarvis from Iron Man. You speak to a continuous presence (Crawdaddy), who acknowledges briefly and orchestrates work in the background. Sub-agents appear as emoji characters performing tasks. The interface is native macOS, not a web app.

**Core interaction model:** You talk *to* Crawdaddy while working. Crawdaddy manages tasks and projects relevant information. This is not conversation with a chatbot—it's a companion that listens, coordinates, and surfaces things when needed.

---

## What We're Building

A working end-to-end prototype that demonstrates:

1. **Continuous voice input** — Speak naturally, Crawdaddy hears you
2. **Brief acknowledgment** — Crawdaddy responds with short spoken confirmation
3. **Task delegation** — Crawdaddy spawns a sub-agent to do work
4. **Visual presence** — Crawdaddy and sub-agents appear as emoji characters on screen
5. **Status visibility** — See when sub-agents are working/done/need input
6. **Input requests** — Sub-agent can surface a question; user clicks to answer

---

## What We're NOT Building

- Sophisticated multi-agent orchestration
- Complex UI/animations
- Persistent memory across sessions
- Multiple simultaneous sub-agents (one at a time is fine)
- Production-quality error handling

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   SwiftUI Native App                    │
│                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐ │
│  │  Crawdaddy  │    │  Sub-Agent  │    │   Speech    │ │
│  │     🦞      │    │     🦀      │    │   Bubble    │ │
│  └─────────────┘    └─────────────┘    └─────────────┘ │
│                                                         │
│  ┌─────────────────────────────────────────────────────┐│
│  │              State Display (minimal)                ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
          │                              ▲
          │ WebSocket                    │ State updates
          ▼                              │
┌─────────────────────────────────────────────────────────┐
│                   Python Backend                        │
│                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐ │
│  │  Crawdaddy  │    │  Sub-Agent  │    │    State    │ │
│  │ Coordinator │───▶│   Runner    │───▶│   Manager   │ │
│  │  (Claude)   │    │  (Claude)   │    │             │ │
│  └─────────────┘    └─────────────┘    └─────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**Two processes:**
1. **SwiftUI app** — Native macOS window with emoji characters, handles speech input/output
2. **Python backend** — Runs Crawdaddy coordinator, manages sub-agents, communicates via WebSocket

---

## Components

### 1. SwiftUI App (Native macOS)

**Responsibilities:**
- Floating transparent window (always visible, doesn't steal focus)
- Render Crawdaddy emoji 🦞 with idle/listening/speaking states
- Render sub-agent emoji 🦀 when active with working/waiting/done states
- Display speech bubbles for responses and questions
- Capture voice input using macOS Speech framework
- Play TTS responses using macOS AVSpeechSynthesizer
- Bidirectional WebSocket connection with backend
- Handle clicks on speech bubbles (for answering sub-agent questions)

**Visual elements:**
- Crawdaddy: 🦞 emoji, visual indicator when listening (glow/pulse/size change)
- Sub-agent: 🦀 emoji, animation when working
- Speech bubble: Rounded rect with text, appears/disappears
- Click target on bubble when sub-agent needs input

**Window behavior:**
- Borderless, transparent background
- Floating level (stays above other windows)
- Click-through except for interactive elements
- Small footprint (bottom-right corner or similar)

### 2. Python Backend

**Responsibilities:**
- WebSocket server for bidirectional communication
- Crawdaddy coordinator agent (Claude API)
- Sub-agent runner (Claude API, async)
- State management (what's running, what's waiting, results)
- Push state updates immediately via WebSocket

**Crawdaddy Coordinator behavior:**
- Receives user transcript
- Returns structured response:
  ```json
  {
    "spoken_response": "On it. I'll look that up.",
    "spawn_task": {
      "description": "Search for recent news about AI",
      "type": "web_search"
    },
    "needs_input": false
  }
  ```
- OR returns simple acknowledgment with no task
- Must be BRIEF — 1-2 sentences max for spoken response

**Sub-Agent behavior:**
- Receives task description from coordinator
- Executes task via Claude API
- Can return:
  - Completed result
  - Question needing user input
- Pushes state updates via WebSocket as work progresses

**State shape:**
```json
{
  "crawdaddy": {
    "state": "idle" | "listening" | "speaking",
    "last_response": "string"
  },
  "sub_agent": {
    "active": true | false,
    "state": "working" | "waiting_for_input" | "done",
    "task_description": "string",
    "question": "string or null",
    "result": "string or null"
  }
}
```

### 3. Voice I/O (in SwiftUI app)

**Input:**
- `SFSpeechRecognizer` for transcription
- Push-to-talk (hold spacebar)
- Send transcript to backend via WebSocket when utterance complete

**Output:**
- `AVSpeechSynthesizer` for TTS
- Crawdaddy speaks responses aloud

---

## Interaction Flow

### Happy Path Example

1. User holds spacebar and says: "Hey Crawdaddy, what's the weather in San Francisco?"
2. SwiftUI app transcribes, sends to backend via WebSocket
3. Backend calls Crawdaddy coordinator (Claude)
4. Crawdaddy returns: `{ spoken_response: "Checking the weather now.", spawn_task: { description: "Get weather for San Francisco", type: "weather" } }`
5. SwiftUI app:
   - Plays TTS: "Checking the weather now."
   - Shows 🦀 sub-agent emoji (working state)
6. Backend runs sub-agent task (Claude call)
7. Sub-agent completes, pushes result via WebSocket
8. SwiftUI app:
   - 🦀 shows "done" state
   - Speech bubble appears with result

### Sub-Agent Needs Input Example

1. User: "Crawdaddy, help me write an email to mom"
2. Crawdaddy: "Sure, I'll draft that. What's the main thing you want to say?"
3. Sub-agent state: `waiting_for_input`, question: "What's the main thing you want to say?"
4. SwiftUI app shows speech bubble with question, clickable
5. User clicks bubble, types or speaks answer
6. Answer sent to backend via WebSocket, sub-agent continues
7. Sub-agent completes with draft email

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Native framework | SwiftUI | Modern, good for floating windows |
| Backend language | Python | Good Claude SDK |
| Backend framework | FastAPI | Async, WebSocket support |
| Communication | WebSocket | Bidirectional, real-time |
| Voice input | Push-to-talk with SFSpeechRecognizer | Simple, reliable |
| Voice output | AVSpeechSynthesizer | Built into macOS |
| LLM | Claude (Anthropic API) | Best for coordination |
| Characters | Emoji | Zero asset work |

---

## File Structure

```
crawdaddy/
├── backend/
│   ├── main.py              # FastAPI + WebSocket server
│   ├── crawdaddy.py         # Coordinator agent logic
│   ├── sub_agent.py         # Sub-agent runner
│   ├── state.py             # State management
│   └── requirements.txt
├── app/
│   └── Crawdaddy/
│       ├── CrawdaddyApp.swift       # App entry point
│       ├── ContentView.swift        # Main floating window
│       ├── EmojiView.swift          # Character rendering
│       ├── SpeechBubbleView.swift   # Bubble component
│       ├── SpeechManager.swift      # Voice I/O
│       └── WebSocketClient.swift    # Backend communication
└── README.md
```

---

## Build Checklist

- [ ] FastAPI WebSocket server that accepts transcripts and pushes state
- [ ] Crawdaddy coordinator (Claude call, structured output, brief responses)
- [ ] Sub-agent runner (Claude call, async, updates state)
- [ ] State manager that tracks crawdaddy + sub-agent state
- [ ] SwiftUI floating transparent window
- [ ] 🦞 emoji with visual states (idle/listening/speaking)
- [ ] 🦀 emoji that appears when sub-agent active (working/waiting/done)
- [ ] Push-to-talk speech recognition (spacebar)
- [ ] TTS playback for Crawdaddy responses
- [ ] WebSocket client in SwiftUI app
- [ ] Speech bubbles for responses and questions
- [ ] Clickable bubble for sub-agent input requests
- [ ] End-to-end flow working

---

## Success Criteria

The prototype is successful if:

1. ✅ User can speak to Crawdaddy using push-to-talk
2. ✅ Crawdaddy responds audibly with brief acknowledgment
3. ✅ 🦀 sub-agent appears when Crawdaddy delegates a task
4. ✅ Sub-agent visually shows working state
5. ✅ Sub-agent result appears in speech bubble when done
6. ✅ The whole thing feels like talking to a presence, not using a chat app

---

## Open Questions

- Window position and size
- How to handle overlapping speech (user talks while Crawdaddy speaking)
- Keyboard shortcut for push-to-talk (spacebar? fn? custom?)
- Whether sub-agent result should also be spoken aloud
- How to gracefully handle errors

---

## Out of Scope (Future)

- Multiple simultaneous sub-agents
- Persistent task memory
- Real tool integrations (web search, file system, calendar)
- Voice wake word ("Hey Crawdaddy")
- Continuous listening without push-to-talk
- Custom voices / ElevenLabs
- Visual task history
- Settings/preferences UI
