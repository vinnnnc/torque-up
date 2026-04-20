# Planned Features

Implementation briefs for features under active design. Each section includes
requirements, acceptance criteria, and rollout notes. Implement in a fresh chat
window with this file as context.

---

## 1. Gear Ratio Propagation

### Motivation

Gears already have tooth counts but angular velocity and torque are not
propagated by ratio through the network. Gear trains produce no mechanical
advantage right now.

### Core Formulas

Speed ratio:

```
omega_out = omega_in * (T_in / T_out)
```

Ideal torque (before losses):

```
tau_out = tau_in * (T_out / T_in)
```

Apply connection/component/zone efficiency losses on top.

### Requirements

- Compute per-edge ratio during network traversal
- Propagate ratio through the full engine-connected path
- Small driving large: reduces RPM, increases torque at output
- Large driving small: increases RPM, reduces torque
- Chain/shaft preserve existing direction rules and still incur expected losses
- Mixed trains produce correct composite ratio
- Do not remove existing friction and efficiency systems; ratio math feeds into them
- Conflict/jam/underpowered overrides still take priority over ratio math

### Acceptance Criteria

- [ ] Small gear driving large gear reduces engine RPM and raises torque
- [ ] Large gear driving small gear raises engine RPM and reduces torque
- [ ] Chain-connected sprockets propagate ratio correctly
- [ ] Composite 3-gear train produces expected aggregate ratio
- [ ] Ratio does not bypass jam or conflict hard-stops

---

## 2. Sprocket Auto-Conversion

### Motivation

Chains use sprockets in reality, not gear teeth. The current system allows chain
to attach to any gear without restriction, which is mechanically incorrect.

### Design

When a player drags a chain to a gear endpoint:

1. Check conversion eligibility (see gate rules below)
2. If eligible: auto-convert the gear to sprocket mode and proceed
3. If ineligible: reject with a clear reason message

### Conversion Gate Rules

| Condition                                | Result            |
| ---------------------------------------- | ----------------- |
| Gear has no active gear-mesh neighbours  | Allow conversion  |
| Gear is currently meshed to another gear | Reject            |
| Gear is in conflict or jam-locked state  | Reject (optional) |
| Gear already in sprocket mode            | Already valid     |

### Mode Rules After Conversion

| Property                          | Gear mode | Sprocket mode            |
| --------------------------------- | --------- | ------------------------ |
| Can mesh with gears               | Yes       | No                       |
| Can connect chain                 | No        | Yes                      |
| Can mount on shaft                | Yes       | Yes                      |
| Can participate in compound stack | Yes       | Yes (as interface layer) |

### Visual Feedback

- Tooth profile or rim style changes to sprocket on conversion
- Badge on converted node: `Sprocket`
- Tooltip line: `Interface: Sprocket (no gear mesh)`
- During chain drag: pre-highlight convertible gears; dim ineligible ones with reason text

### Rejection Messages

- `Cannot convert to sprocket: gear is meshed to another gear.`
- `Disconnect meshed neighbours first.`

### Reversion

If chain is removed, offer optional reversion to gear mode.

### Acceptance Criteria

- [ ] Chain placement on unmeshed gear auto-converts and succeeds
- [ ] Chain placement on meshed gear is rejected with correct message
- [ ] Converted sprocket cannot form new gear-mesh connections
- [ ] Converted sprocket can still mount on shaft
- [ ] Visual state updates immediately on conversion
- [ ] Rejection message is correct for every gate condition

---

## 3. Compound Gear Stacks

### Motivation

Compound gears (coaxial elements on one shaft) allow compact ratio changes,
interface bridging between gear trains and chain lines, and richer topology
decisions without adding new placeable parts.

### Definitions

- **Compound stack**: two coaxial elements sharing a shaft node
- **Element**: one gear or one sprocket within the stack
- **Layer**: position in the stack (inner = smaller, outer = larger)

### Stack Eligibility Rules

| Pairing                                  | Allowed                        |
| ---------------------------------------- | ------------------------------ |
| Small inside Medium or Large (gear+gear) | Yes                            |
| Medium inside Large (gear+gear)          | Yes                            |
| Same size gear + gear                    | No                             |
| Same size gear + sprocket                | Yes (different interface type) |
| Larger inside smaller                    | No                             |
| More than 2 layers (Phase 1)             | No                             |

### Mechanical Rules

- Elements on the same shaft share angular velocity (rigid coupling)
- Each element has its own external interface: gear mesh or chain
- No single element can act as both gear-mesh and chain interface
- Each compound layer adds a tunable efficiency penalty
- Each compound layer adds a tunable inertia/response penalty (heavier spin-up)

### Sprocket Conversion Interaction

- Sprocket elements in a compound stack follow the same conversion gate rules as standalone gears
- If any gear element in the stack is currently meshed, sprocket conversion on the same stack is blocked

### Rollout Plan

| Phase   | Scope                                                                 |
| ------- | --------------------------------------------------------------------- |
| Phase 1 | 2-layer only; gear+gear and gear+sprocket combinations                |
| Phase 2 | Compound tooltip showing per-layer ratio, RPM, torque, interface type |
| Phase 3 | Efficiency and inertia penalty tuning pass                            |
| Phase 4 | 3-layer if gameplay justifies it                                      |

### Acceptance Criteria

- [ ] Smaller gear can stack inside larger gear on same shaft
- [ ] Same-size gear+gear stack is blocked with feedback
- [ ] Larger-inside-smaller stack is blocked with feedback
- [ ] Same-size gear+sprocket stack is allowed
- [ ] Both elements share angular velocity correctly
- [ ] Efficiency penalty applies per added layer
- [ ] Sprocket conversion gate applies within compound stacks
- [ ] Max 2 layers enforced in Phase 1

---

## 4. Zone Contribution View

### Motivation

Layer 1 hover tooltips and the Layer 2 network overlay now ship in the game.
The remaining readability gap is zone contribution: players still cannot see
how heat, cold, and dust change local or network performance without inferring
it indirectly from tint and output changes.

### Current Shipped Layers

- Layer 1: component hover tooltip with state badges, RPM, torque, friction/load, and type-specific details
- Shift + hover: expanded raw values for the hovered component
- Layer 2: toggleable network overlay showing delivered torque, engine RPM, efficiency, friction load, connected source count, underpowered state, and current bottleneck

### Layer 3 — Zone Contribution View (contextual)

Triggered by hovering a component inside a zone or selecting zone-view mode.

- Active zone modifiers on this component or network
- Before/after values for torque, RPM, and efficiency
- Per-zone deltas showing route penalty or bonus clearly

### UX Behaviour

| Interaction         | Result                              |
| ------------------- | ----------------------------------- |
| Hover component     | Existing Layer 1 tooltip            |
| Shift + hover       | Existing expanded raw-value tooltip |
| Toggle key (Q)      | Existing Layer 2 network overlay    |
| Zone mode key (TBD) | Layer 3 zone shading + deltas       |

### Implementation Priority

1. Layer 3 — advanced tuning and puzzle teaching

### Acceptance Criteria

- [ ] Zone panel appears only when contextually relevant
- [ ] Zone panel shows active zone types and intensity on the hovered component
- [ ] Zone panel shows before/after torque, RPM, and efficiency values clearly
- [ ] Zone view makes multi-zone overlap readable without hiding core motion cues
- [ ] Tooltip is readable in dense builds without clipping

---

## 5. Documentation Updates

Update `docs/current-state/` as each feature ships:

| File              | Updates needed                                                                   |
| ----------------- | -------------------------------------------------------------------------------- |
| `simulation.md`   | HP formula, RPM derivation, torque-ratio flow, `delivered_torque` definition     |
| `components.md`   | Sprocket mode, compound stack rules, ratio behaviour per connector type          |
| `ui-and-world.md` | Current tooltip/overlay layers, overlay toggle, remaining zone contribution view |
| `README.md`       | Add sprocket, compound, ratio, overlay to feature summary                        |

---

## 6. Torque Frontier Unlock (Fog Of Work)

### Motivation

Early builds can route to far power nodes too quickly, reducing the intended
local optimization phase around the engine.

This mechanic turns mechanical progress into spatial progress: stronger
engine-path torque unlocks more buildable world around the engine.

### Core Design

- The map starts with a circular unlocked radius around the central engine.
- Outside this radius, world space is fogged and blocked for placement/snap.
- Unlock radius expands based on torque performance.
- Radius growth is persistent: once unlocked, it never shrinks.

### Progress Signal

Use a smoothed torque signal to avoid one-frame spikes dominating progression.

```
smoothed_torque_t = alpha * delivered_torque_t + (1 - alpha) * smoothed_torque_(t-1)
```

```
candidate_radius = base_radius + k * sqrt(smoothed_torque_t)
unlocked_radius = max(unlocked_radius, candidate_radius)
```

### Why This Shape

- Smoothing rewards sustained performance over transient spikes
- `sqrt` growth gives diminishing returns and prevents runaway expansion
- Persistent max radius avoids frustrating "map reclosing" when torque dips

### Rules

- Expansion authority: engine-connected delivered torque only
- Disconnected source islands do not unlock fog radius
- Fog blocks placement and snap origins beyond unlocked radius
- Existing placed components remain valid if torque later drops

### UX

- Circular frontier ring visible around current unlocked boundary
- Subtle fog mask outside frontier
- Progress bar in HUD: current smoothed torque vs next radius threshold
- Optional text hint: `Next frontier expansion at X torque`

### Tuning Inputs

- `base_radius`
- `alpha` smoothing factor
- `k` radius gain scalar
- minimum expansion step (optional snap-to-rings)
- max radius clamp (optional per-level cap)

### Acceptance Criteria

- [ ] Initial radius encloses the intended early-game puzzle area
- [ ] Fogged space blocks placement and snapping outside unlocked frontier
- [ ] Unlock radius expands from sustained delivered torque increases
- [ ] Short torque spikes do not cause oversized expansions
- [ ] Radius does not shrink when torque drops
- [ ] Progress UX clearly communicates current progress and next threshold

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

## Rollout Order

| Phase | Feature                                                      |
| ----- | ------------------------------------------------------------ |
| A     | Gear ratio propagation through network traversal             |
| B     | Sprocket auto-conversion with gate rules and visual feedback |
| C     | Compound gear stacks (2-layer, Phase 1 only)                 |
| D     | Zone contribution view (Layer 3)                             |
| E     | Torque frontier unlock (fog progression gate)                |
| F     | Session management and personal best tracking                |
| G     | Docs and balancing pass                                      |

---

## Test Matrix

### Functional

- [ ] Single-source straight gear train
- [ ] Multi-source merged train (with differential)
- [ ] Chain-heavy layout with sprocket auto-conversion
- [ ] Compound gear train across gear+sprocket layers
- [ ] Zone-heavy layout
- [ ] Frontier unlock progression from low to high torque builds
- [ ] Underpowered, jam, and conflict scenarios

### Numerical Sanity

- [ ] HP monotonicity with RPM and torque
- [ ] Ratio composition across 2–5 gear chain
- [ ] Efficiency impacts HP exactly as a multiplier
- [ ] No negative HP or RPM artifacts

### UX

- [ ] Hover info readable in dense builds
- [ ] Overlay toggle latency acceptable
- [ ] Zone panel appears only when contextually relevant
- [ ] Frontier ring and fog boundary remain readable in dense builds
- [ ] Rejection messages fire on every gate violation
- [ ] Sprocket badge visible immediately after conversion
