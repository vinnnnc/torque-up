# Planned Features

Planning backlog for items not yet shipped.

Document split:

- Implemented features archive (former sections 1-6): `docs/implemented-features.md`
- Latest feature track (former section 8+): `docs/latest-features.md`
- This file now keeps deferred feature 7, which is intentionally scheduled last.

---

## Implemented Features (Archived)

Features 1-6 are already implemented and moved to:

- `docs/implemented-features.md`

Use current behavior docs for source-of-truth runtime behavior:

- `docs/current-state/README.md`
- `docs/current-state/components.md`
- `docs/current-state/simulation.md`
- `docs/current-state/placement-and-editor.md`
- `docs/current-state/ui-and-world.md`

---

## 7. Session Management and Personal Best

### Motivation

Sandbox/endless optimization games benefit from persistent session tracking and local personal best records rather than competitive leaderboards. This keeps focus on self-improvement iteration and accommodates both speedrunners (optimize time) and perfectionists (maximize HP).

### Design

No multiplayer ranking system. Instead:

- **Auto-save on exit**: Session state (components, connections, lifetime_hp, duration) saved locally
- **Personal best tracking**: One entry per player: highest lifetime_hp ever achieved, with timestamp and session duration
- **Resume capability**: Player can resume last session from exact saved state or start fresh
- **HUD display**: "Personal Best: X HP" in corner; "New personal best!" on exit if current session beats record

### Session Lifecycle

1. Player starts new session → components clear, lifetime_hp = 0
2. Builds network, accumulates lifetime_hp via: `lifetime_hp += horsepower * delta * reliability_multiplier`
3. Player quits → session auto-saved as JSON (`personal_best.json`)
4. Personal best updated only if lifetime_hp exceeds stored value
5. Next session offers "Resume" or "New Game" option

### Storage Format

```json
{
    "lifetime_hp": 487.5,
    "session_duration_seconds": 283,
    "timestamp": "2026-04-20T14:32:00Z",
    "component_count": 14,
    "efficiency_ratio": 0.78
}
```

### Acceptance Criteria

- [ ] Session state (components, connections) persists on exit and reloads on resume
- [ ] Lifetime HP counter resumes from saved value, not reset to 0
- [ ] Personal best stored and updated correctly (only on improvement)
- [ ] HUD displays current personal best during gameplay
- [ ] "New personal best!" message shown when current session exceeds record
- [ ] "New Game" clears all components and resets lifetime_hp
- [ ] Resume/New Game options clear and intuitive in menu

### Gameplay Impact

- Encourages iteration: players refine layouts over multiple sessions without full restart
- Removes ranking pressure: no comparison against others, focus on self-improvement
- Supports varied play styles: speedrunners optimize for time; perfectionists for HP
- Avoids technical debt: no server, no synchronization, local-only JSON

---

## 8+ Latest Feature Track

Latest feature planning (former section 8 and follow-ups) moved to:

- `docs/latest-features.md`

Section 7 remains intentionally last in the delivery order.
