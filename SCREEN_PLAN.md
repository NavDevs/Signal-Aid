# Signal Aid — Screen Plan (Emergency Vehicle App)

Screen-by-screen plan for **Component 2 of 3**: the Signal Aid Emergency Vehicle Mobile App.
Every screen is mapped to the spec workflow (§1–§22), to a backend call, to a socket event, and
to the exact status transition it is allowed to cause.

Legend: **[EXISTS]** already in the repo · **[REWORK]** exists but does not meet spec · **[NEW]** to build.

---

## 1. Where this app sits in the system

```
USER MOBILE APP
      │  photo + description + GPS
      ▼
BACKEND SERVER  ──►  IMMEDIATE DISPATCH  (accident/fire → DISPATCHED at once, others stay ACTIVE)
      │
      ▼
INCIDENT MANAGEMENT  (status is the single source of truth, server-side only)
      │
      ▼
DISPATCH ENGINE  (nearby approved + AVAILABLE vehicles, first-accept-wins, atomic lock)
      │
      ▼
SIGNAL AID MOBILE APP   ← you are here (steps 5–11 below)
```

Signal Aid is a **driver client only**. It never decides: not verification, not eligibility, not
who won the job, not the status. It renders backend truth and sends GPS + driver intent.

Signals that cross the boundary:

| Direction | Signal | Transport |
|---|---|---|
| Backend → App | new verified emergency request | socket `dispatch.created` |
| Backend → App | job taken by another driver | socket `dispatch.accepted` |
| Backend → App | assigned to you / cancelled / status change | socket `dispatch.*` |
| Backend → App | approval decision | socket `driver_approval_updated` |
| App → Backend | accept job (race) | `POST /api/dispatches/:id/accept` |
| App → Backend | live GPS + availability | `PATCH /api/driver/location`, `PATCH /api/driver/availability` |
| App → Backend | progress states | `PATCH /api/dispatches/:id/status` |

---

## 2. Screen map

```
                        ┌──────────────────────┐
                        │ S0 Splash / Restore  │  [BUILT]
                        └──────────┬───────────┘
                                   │ validate stored token
        ┌──────────────────┬───────┴────────┬───────────────────┐
        ▼                  ▼                ▼                   ▼
 ┌─────────────┐   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
 │ S1 Sign-In  │   │ S3 Approval  │  │ S2 Register  │  │ S4 Duty      │
 │  [REWORK]   │   │   Pending    │  │  [EXISTS]    │  │  Dashboard   │
 └──────┬──────┘   │  [EXISTS]    │  └──────┬───────┘  │  [REWORK]    │
        │          └──────────────┘         │          └──────┬───────┘
        │ register →└──────────────────────►┘                 │ accepts
        │                                                      ▼
        │                                          ┌──────────────────────┐
        │                                          │ S5 Job Detail        │
        │                                          │  (ACCEPT / DECLINE)  │
        │                                          └──────────┬───────────┘
        │                                                     │ 200 OK
        │                                                     ▼
        │                                          ┌──────────────────────┐
        │                                          │ S6 Active Response   │
        │                                          │  map · route · nav   │
        │                                          │ [REWORK — real map]  │
        │                                          └──────────┬───────────┘
        │                                        EN_ROUTE → ARRIVED → RESOLVED
        │                                                     │
        └────────────► S9 Profile & Settings ◄────── S8 History [EXISTS]
```

Global overlays (no route): **location permission gate**, **session-invalidated dialog**,
**"job taken / cancelled" banner**.

---

## 3. Route table

| Route | Screen | Guard |
|---|---|---|
| — (boot) | S0 Splash / Session Restore | none |
| `/login` | S1 Driver Sign-In | redirect away if session valid |
| `/register` | S2 Driver Registration Request | none |
| `/approval` | S3 Approval Pending / Rejected | requires known driver id |
| `/` | S4 Duty Dashboard | valid session + `approval_status == approved` |
| `/job` | S5 Incoming Request Detail | S4 + candidate for the dispatch |
| `/response` | S6 Active Response | valid session + assignment owned by this driver |
| `/history` | S8 Assignment History | valid session |
| `/profile` | S9 Profile & Settings | valid session |

Rule: **no screen may be reachable that the backend would reject.** The router guard mirrors
server-side checks; it is a UX convenience, never the security boundary.

---

## 4. Screen specifications

### S0 — Splash / Session Restore **[BUILT]**

**Purpose.** Enforce spec §7 ("login once"): restore a stored token on cold start and route the
driver to the right screen without re-typing credentials.

**What the driver sees.** Logo + spinner, under 2 s. No input.

**What the driver does.** Nothing.

**What the app must do.**
1. Read the persisted session (token + driver profile).
2. If nothing stored → `/login`.
3. If stored → `GET /api/driver/profile` with `Authorization: Bearer <token>`.
4. Branch on the response:
   - `200` + `approval_status == approved` → persist refreshed profile → `GET /api/dispatches/nearby` → `/`.
   - `200` + `pending` / `rejected` → `/approval`.
   - `401/403` → wipe session → `/login` (spec §7: logout on security invalidation).
   - network failure → if a cached session exists, enter `/` in **offline** mode (banner, jobs
     disabled) rather than forcing a logout; retry with backoff.

**Backend calls.** `GET /api/driver/profile` *(requires `authMiddleware, requireApprovedDriver`)*.

**Socket events.** None yet; socket connects after the session is confirmed.

**Transitions caused.** None.

**Why this screen matters.** The current app boots by reading a local JSON file and trusting it —
a rejected or de-approved driver would still reach the job list. The restore call is the fix.

---

### S1 — Driver Sign-In **[BUILT]**

**Purpose.** Authenticate an already-approved driver; spec §6/§7.

**What the driver sees.**
- Signal Aid brand block, red theme (`AppColors.primary`).
- Field 1: **Driver ID** (the human code, e.g. `AMB-1187`).
- Field 2: **Vehicle Number** (e.g. `AMB-1187`).
- Primary button: **Active Response** (sign in).
- Secondary button: **New Driver? Register for Approval** → `/register`.
- Inline error panel (danger colours) for wrong credentials / rejected / network.

**What the driver does.**
1. Enter Driver ID and Vehicle Number.
2. Press sign in.
3. On success, land on S4 with availability still `OFFLINE` (see S4 — going on duty is a
   deliberate, separate action).

**Backend calls.** `POST /api/auth/driver/login` → `{ token, user: { id, driver_id, name, phone,
vehicle_no, vehicle_type, organization, approval_status } }`.

**Branching on the response.**
| Server answer | Screen behaviour |
|---|---|
| `200`, approved | persist token + profile, go to `/` |
| `200`/`403`, `approval_status: pending` | go to `/approval` |
| `403`, `approval_status: rejected` | go to `/approval` (rejected variant) with reason |
| `401` | inline "Driver ID or vehicle number is incorrect" |
| `5xx` / timeout | "Could not reach server. Check internet and try again." |

**Guards.** Client never stores an approval decision; it stores what the server said and re-checks
on every boot (S0) and every duty toggle (S4).

**Error/edge paths.** Trim + uppercase inputs. Disable the button while in flight (already done via
`_busy`). Never show a raw stack trace or a status code to the driver.

---

### S2 — Driver Registration Request **[EXISTS — audit fields]**

**Purpose.** `NEW DRIVER → Registration Request → Backend → Admin Review` (spec §6).

**Form fields (must all be present and reach the backend).**
| Field | Required | Notes |
|---|---|---|
| Full name | yes | |
| Phone number | yes | contact for dispatch problems |
| Driver ID | yes | unique human code used at sign-in |
| Vehicle number | yes | must match at login |
| Vehicle type | yes | `ambulance` \| `fire` \| `other` — decides which emergencies you receive |
| Organization | yes | hospital / fire station / operator |
| Authorization / identity info | yes per spec §6 | licence or service ID; may be a text reference today, a document upload later |

**What the driver does.** Fill the form → submit → land on S3 with `pending`.

**Backend calls.** `POST /api/auth/driver/register` → creates the user (`role = DRIVER`,
`approval_status = pending`) **and** a row in `driver_approval_requests`.

**Validation to enforce client-side (mirrors server).** Non-empty name/phone/vehicle;
vehicle type from a fixed list; phone shape. Server re-validates — client checks are UX only.

**Error/edge paths.** Duplicate driver ID or vehicle number → inline "already registered, contact
admin". After a rejection, allow **re-submission** (new request row), never a silent edit of the
approved record.

---

### S3 — Approval Pending / Rejected **[BUILT]**

**Purpose.** Hold the driver while an admin reviews (spec §6: rejected drivers cannot use dispatch).

**What the driver sees.**
- `pending`: hourglass/pulse, "Your registration is under review", submitted fields recap
  (name, vehicle, org), "We'll notify you the moment you're approved".
- `rejected`: red banner + **rejection reason** from the admin, and a **Re-submit** button → S2.
- Buttons: **Refresh status**, **Log out**.

**What the driver does.** Waits; may refresh or log out. Cannot reach `/` — the guard blocks it even
if the driver deep-links.

**Backend calls.** `GET /api/driver/profile` on refresh.

**Socket events.** `driver_approval_updated` → immediately re-fetch profile; on `approved`, show a
success toast and navigate to `/`.

**Transitions caused.** None in the incident model — this is a driver-account state.

**Edge path.** If an **already-approved** driver is later revoked while signed in, the same event
must bounce them back here (spec §17: "the backend must re-check approval status every time").

---

### S4 — Duty Dashboard **[REWORK of `dispatch_screen.dart`]**

**Purpose.** The driver's home: go on duty, share location, see live emergency requests.
This replaces the current "Pre-flight / Plan Response" screen, whose `DispatchHelper` fake
ETA + 5 hardcoded intersections + decorative grid map have no place in the spec.

**Layout, top to bottom.**

1. **Profile strip** — driver ID chip, vehicle number chip, organization, `OPEN HISTORY` and
   `PROFILE` icon buttons. **[NEW]**
2. **Duty switch — `OFFLINE ⇄ AVAILABLE`** **[NEW]**
   - Turning **ON**: (a) resolve location permission, (b) `PATCH /api/driver/availability
     { availability: "AVAILABLE" }`, (c) start the GPS uplink loop, (d) start polling/fetching
     nearby dispatches.
   - Turning **OFF**: `PATCH /api/driver/availability { availability: "OFFLINE" }`, stop the uplink.
   - **Cannot turn OFF while assigned** — the switch is disabled and shows "On assignment".
3. **Status bar** — socket connected?, GPS fix age, current availability. **[NEW]**
4. **Active assignment banner** **[NEW]** — if the backend says this driver owns a live
   assignment (e.g. app was killed mid-response), a red card: "You are assigned to a FIRE incident"
   with **Resume**. This is the recovery path required by §21 and stops a driver losing a job to an
   app crash.
5. **EMERGENCY JOBS list** — one card per incoming dispatch from
   `GET /api/dispatches/nearby?lat&lon&vehicle_type&radiusKm` plus live `dispatch.created` pushes.

**Job card content (spec §4, §16 — this is what makes notifications usable).**
| Element | Source |
|---|---|
| Incident type badge (`ACCIDENT` / `FIRE` / `OTHER`) | `dispatch.type` |
| Vehicle required (`AMBULANCE` / `FIRE`) | `dispatch.required_vehicle` |
| Verification status (always `VERIFIED`) | `dispatch.status` |
| Description / address | `dispatch.description`, `dispatch.address` |
| General location + straight-line distance from me | `dispatch.latitude/longitude` + my GPS |
| Time since reported | `dispatch.created_at` |
| Severity, when available | `dispatch.severity` (render "—" when absent — never invent it) |
| **VIEW & ACCEPT** → S5 | — |

**What the driver does.**
1. Sign in (S1) → toggle duty ON → grant location.
2. Watch the list; new verified jobs appear without a manual refresh.
3. Open a job → S5.

**Backend calls.** `PATCH /api/driver/availability`, `GET /api/dispatches/nearby`,
`GET /api/dispatches`, `GET /api/driver/profile`.

**Socket events consumed.** `dispatch.created` (insert job — **filter by `required_vehicle`
comparing to my `vehicle_type`**), `dispatch.accepted` (remove job, plus banner if it was mine),
`dispatch.cancelled`, `driver.availability_updated` (multi-device sync), `driver_approval_updated`.

**Transitions caused.** Driver availability: `OFFLINE → AVAILABLE → BUSY → AVAILABLE`.

**Edge paths.** Empty list → friendly "No active emergencies" with "Listening for nearby verified
emergencies". Duplicate dispatch ids must be de-duplicated (socket push + poll race). Offline →
banner + retry, queue nothing.

---

### S5 — Incoming Request Detail **[NEW]**

**Purpose.** Give the driver enough context to commit, and be the front line of the
**first-accept-wins race** (spec §8).

**What the driver sees.**
- Full-width alert header: `🚨 VERIFIED ACCIDENT` / `🔥 VERIFIED FIRE` with the pulse animation.
- Incident block: description, general location text, coordinates, reported-at timestamp,
  severity if present, photo thumbnail if the backend exposes it.
- Distance + straight-line proximity ("2.4 km away"), **not** a fabricated ETA.
- Acceptance countdown (soft — purely informational; expiry is decided by the backend).
- **ACCEPT** (large, red) and **DECLINE** (dismiss back to S4; the job stays in the list).

**What the driver does.** Read the details → ACCEPT or DECLINE. ACCEPT is the only action that
mutates server state.

**Backend calls.** `POST /api/dispatches/:id/accept { driver_id, vehicle_no }` with the bearer token.

**Response handling — this screen is defined by its failure modes.**
| Status | Meaning | Screen behaviour |
|---|---|---|
| `200` | won the job | persist trip id + dispatch, disable the button, go to `/response` |
| `409` | already accepted by someone else | "Taken by another driver" → auto-return to S4, remove the job |
| `403` | not approved / wrong vehicle type / not available | show reason, return to S4, refresh duty state |
| `401` | session invalid | session-invalidated dialog (S0 path) |
| `5xx`/timeout | unknown | **do not** assume success or failure — re-fetch the dispatch and branch on its real status |

**Socket events.** `dispatch.accepted` may arrive *before* the HTTP response returns; the app must
treat that event as authoritative and cancel the in-flight accept UI.

**Transitions caused.** `VERIFIED → DISPATCHED` (created by the backend when the request goes out)
and `DISPATCHED → ACCEPTED` on the winning accept.

**Edge path — the critical rule.** Even if two drivers tap simultaneously, exactly one gets `200`;
the loser gets `409` and never sees S6. The client must never optimistically navigate to S6 before
the server confirms.

---

### S6 — Active Response: Map, Route, Navigation **[REWORK — this is the biggest change]**

**Purpose.** Execute the drive. Covers spec §10 (map), §11 (shortest/fastest route), §12/§13
(navigate → ARRIVED → RESOLVED).

Today this screen shows a **fake** plan (`DispatchHelper.computeDispatchPlan`), a **simulated**
countdown and preemption list, a **decorative** grid "map", and a Google Maps **intent** for
navigation. All of that is replaced by real coordinates, real routing and a real map.

**Layout, top to bottom.**

1. **Alert frame + banner** — keep the red border and the pulsing "Emergency vehicle en route"
   banner, but bind the label to the live status: `ACCEPTED` → "Assignment confirmed",
   `EN_ROUTE` → "En route to scene", `ARRIVED` → "On scene", `RESOLVED` → "Response complete".
2. **Real map (the centrepiece)** — `flutter_map` + OSM tiles, the **same map stack Roadly
   already uses** (`flutter_map ^8.3.2` + `latlong2 ^0.10.1`; Signal Aid's `pubspec.yaml` has
   neither, so add both).
   - 🚑 marker = my live GPS (§9).
   - 🚨 marker = the incident's stored `latitude/longitude` (sent with the assignment, §21 "send
     incident location").
   - Blue polyline = the route geometry returned by the routing provider.
   - Camera auto-fits both markers; a recentre FAB returns to my position.
3. **Route metrics row** — **Distance**, **ETA**, and a traffic/baseline indicator, all from the
   routing response. No client-side estimation, no fabricated confidence percentage.
4. **Turn-by-turn instruction list** — the manoeuvres from the same routing response; the current
   step is highlighted and advances as we move. **[NEW]**
5. **`START NAVIGATION`** — spec §10. Hands off to a real navigation surface:
   - primary: launch the device navigation app with a driving route to the incident
     (`url_launcher`, the existing `https://www.google.com/maps/dir/?api=1&destination=lat,lon&travelmode=driving`
     intent already in the code);
   - secondary: in-app follow-mode on the `flutter_map` view that keeps the camera on the vehicle.
   Either way the provider does the road routing — never hand-roll it (§10/§11).
6. **GPS uplink indicator** — "GPS tracking active · updating every 5 s" (already present) plus the
   timestamp of the last accepted fix, so a driver can tell when the uplink has gone quiet.
7. **Status stepper** — `ACCEPTED → EN_ROUTE → ARRIVED → RESOLVED` rendered as a vertical stepper
   so the driver always knows where they are. **[NEW]**
8. **Action buttons** — exactly two, staged:
   - **START RESPONSE** (`EN_ROUTE`) — shown while `ACCEPTED`; marks departure from base.
   - **MARK ARRIVED** (`ARRIVED`) — big success button.
   - **RESOLVE INCIDENT** (`RESOLVED`) — replaces it after arrival; releases the assignment and
     returns duty to `AVAILABLE`.
9. **Mini assigned-driver block** — my ID, unit, vehicle type, organization (keep the existing card).

**What the driver does.**
1. Arrives here only with a confirmed acceptance.
2. Presses **START NAVIGATION** and follows the route.
3. Presses **START RESPONSE** to declare `EN_ROUTE` (sets availability `BUSY` server-side).
4. Drives; the app uplinks GPS every 5 s and the ETA counts down from real route data.
5. On scene → **MARK ARRIVED**.
6. Handover done → **RESOLVE INCIDENT**.

**Backend calls.**
- `PATCH /api/dispatches/:id/status { status: "en_route" | "arrived" | "resolved" }` — the
  assignment status.
- `POST /api/trips/:id/location { latitude, longitude }` and
  `PATCH /api/driver/location { latitude, longitude, availability: "BUSY" }` — the existing
  every-5-seconds uplink.
- `GET /api/route?fromLat&fromLon&toLat&toLon` — routed through the backend so the provider key and
  OSRM usage stay server-side (the endpoint already exists and already falls back to haversine).
- Refresh the route when the driver has moved meaningfully (e.g. >250 m since the last fetch) rather
  than on every fix, to stay inside provider rate limits.

**Socket events consumed.** `dispatch.cancelled` → stop navigation, release the job, return to S4
with a warning banner. `dispatch.assigned` (re-assignment by an admin) → follow the new assignment.

**Transitions caused.** `ACCEPTED → EN_ROUTE → ARRIVED → RESOLVED`. The backend is the one that
persists these; the UI only ever *requests* a transition and then renders what the server confirms.

**Guards.** `PATCH` must carry the bearer token so the backend can verify **assignment ownership**
(§17: only the assigned driver may update their active emergency). A driver who opens `/response`
without owning the assignment gets bounced to S4.

**Edge paths.**
| Situation | Behaviour |
|---|---|
| Location permission denied | blocking gate before duty; the screen shows "Location required for dispatch" and no GPS-dependent metrics |
| Location services off mid-trip | banner + retry every 15 s; keep the last known fix and its age |
| Routing provider down | fall back to the backend's haversine distance + a "no traffic data" ETA label — still show the markers |
| App killed mid-response | S0/S4 restore finds the active assignment and offers **Resume** into this screen |
| Another driver somehow accepted first | `409` on the next status PATCH → full-screen "This emergency was reassigned" → S4 |
| Resolve pressed twice / double-tap | disable both buttons in flight; server is idempotent on status |

---

### S8 — Assignment History **[EXISTS — align fields]**

**Purpose.** The driver's record of completed emergency responses.

**What the driver sees.** Reverse-chronological list: date/time, incident type, vehicle, distance,
duration, criticality — sourced from `GET /api/trips/:driver_id` (or the assignment endpoint).

**What the driver does.** Scrolls; taps a row for the detail sheet. Read-only.

**Known bug to fix.** The row currently renders mostly `—` because the list is populated from the
trip payload while the display fields (criticality, time, distance) come from columns the
assignment flow does not write. Decide on **one** source of truth — the assignment (`incidentId`,
`acceptedAt`, `arrivedAt`, `resolvedAt`, computed distance/duration) — and render from that.

**Empty state.** "No previous responses yet" — not an empty table.

---

### S9 — Profile & Settings **[BUILT — notifications row still owed]**

**Purpose.** Spec §7: the only place a session ends, plus the driver's own compliance view.

**What the driver sees.** Name, Driver ID, phone, vehicle number, vehicle type, organization,
**approval status badge** (approved/pending/rejected), app version, and:
- **Location permission** row with current state + "Open settings".
- **Notification permission** row.
- **Log out** (single, confirming).

**What the driver does.** Reviews identity data, fixes a permission, or logs out. Anything
corrective (changing vehicle, organization, licence) routes to **Contact admin** — a driver must
never be able to edit the fields an admin approved.

**Backend calls.** `GET /api/driver/profile`; `PATCH /api/driver/availability { OFFLINE }` on logout.

**Socket events.** Disconnect the socket on logout; the token is revoked/cleared.

---

## 5. Global overlays & cross-screen behaviour

| Overlay | Trigger | Behaviour |
|---|---|---|
| **Location permission gate** | duty ON without permission | modal explaining why GPS is required (§9); grant → continue; deny-forever → "Open settings" + duty stays OFF |
| **Session invalidated** | any `401`/`403` from a guarded call | wipe session, "Your session ended. Please sign in again" → S1 |
| **Approval revoked** | `driver_approval_updated` → pending/rejected | stop GPS uplink, set `OFFLINE`, dismiss any open job, → S3 |
| **Job taken / cancelled banner** | `dispatch.accepted` / `dispatch.cancelled` | non-blocking red banner; removes the job from S4 and tears down S6 if it was active |
| **Offline banner** | socket down or requests failing | "No connection — you will not receive new emergencies"; a driver must always know this |
| **Foreground alert** | `dispatch.created` for my vehicle type while on another screen | in-app alert card (and a push/local notification per §16) with a direct route into S5 |

---

## 6. Status model, and who is allowed to move what

Single chain (spec §14/§21), **backend-owned**:

```
ACTIVE → DISPATCHED → ACCEPTED → EN_ROUTE → ARRIVED → RESOLVED
   └────────────────────────────────────────────── ↘ REJECTED (admin)
```

| Transition | Caused by | Signal Aid's role |
|---|---|---|
| `ACTIVE → DISPATCHED` | citizen reports accident/fire (immediate) | receives `dispatch.created` |
| `DISPATCHED → ACCEPTED` | **first driver to accept** | the `POST /accept` that wins |
| `ACCEPTED → EN_ROUTE` | assigned driver | **START RESPONSE** |
| `EN_ROUTE → ARRIVED` | assigned driver | **MARK ARRIVED** |
| `ARRIVED → RESOLVED` | assigned driver (or admin) | **RESOLVE INCIDENT** |

Drivers **never** see or set `ACTIVE` or `REJECTED` — they only ever receive dispatchable
work. That is what keeps spec §3 ("do not show unverified incidents as confirmed") true by
construction.

Driver availability (`OFFLINE / AVAILABLE / BUSY`) and assignment status move together:
going `EN_ROUTE` implies `BUSY`; resolving implies `AVAILABLE`.

---

## 7. What the backend must offer for these screens

| Screen | Endpoint | Guard |
|---|---|---|
| S0/S9 | `GET /api/driver/profile` | token + approved |
| S1 | `POST /api/auth/driver/login` | public |
| S2 | `POST /api/auth/driver/register` | public |
| S4 | `PATCH /api/driver/availability` | token + approved |
| S4 | `GET /api/dispatches/nearby` | token + approved + available |
| S5 | `POST /api/dispatches/:id/accept` | token + approved + available + **atomic lock** |
| S6 | `GET /api/route` | token |
| S6 | `POST /api/trips/:id/location`, `PATCH /api/driver/location` | token + approved + assignment owner |
| S6 | `PATCH /api/dispatches/:id/status` | token + approved + **assignment owner only** |
| S8 | `GET /api/trips/:driver_id` | token + self |

Socket: `dispatch.created`, `dispatch.accepted`, `dispatch.cancelled`, `dispatch.assigned`,
`driver_approval_updated`, plus a driver-location feed for the admin dashboard.

---

## 8. Gap analysis — plan vs. what exists today

| # | Item | State | Action |
|---|---|---|---|
| 1 | S0 session restore validated by backend | **done** — `restoreSession()` calls `GET /api/driver/profile`, falls back to stored credentials on `401`, keeps a cached session offline | — |
| 2 | Approval pending / rejected screens wired to live events | **done** — `driver_approval_updated` re-checks; rejected state shows the admin's reason | — |
| 3 | Duty availability toggle (`OFFLINE ⇄ AVAILABLE`) | missing | build on S4; cannot go offline while assigned |
| 4 | GPS uplink outside an active response | missing | uplink on duty ON, not only inside S6 |
| 5 | Resume-after-crash active assignment | missing (`fetchActiveTrip` only logs) | expose it as the S4 banner → S6 |
| 6 | Job detail screen with real accept race handling | missing (ACCEPT is inline) | build S5 with `409` handling |
| 7 | Real map (`flutter_map` + `latlong2`) | missing — decorative grid | add deps (same versions as Roadly) |
| 8 | Route polyline + turn instructions | missing | render `/api/route` geometry |
| 9 | `START NAVIGATION` | partial (Google Maps intent only) | keep the intent as primary, add in-app follow mode |
| 10 | Fabricated ETA / speed / confidence / "preempted" intersections | present (`DispatchHelper`) | delete; drive the UI from `/api/route` + real status |
| 11 | Status stepper `ACCEPTED → EN_ROUTE → ARRIVED → RESOLVED` | partial (two buttons) | add `START RESPONSE` + stepper |
| 12 | Explicit `en_route` transition | missing | wire `START RESPONSE` |
| 13 | Profile & Settings (+logout, permissions) | **done** — S9 shows identity, approval badge, location permission and logout; notification row still owed | add the notification permission row |
| 14 | Notification permission + in-app foreground alert | missing | add on duty ON |
| 15 | History rows rendering `—` | **backend fixed** — the accept flow now writes `criticality`/`distance`/`confidence`, so new trips carry real values; S8 still has to render them | render the stored fields in S8 |
| 16 | Dead Supabase path (`services/*`, `config/supabase_config.dart`, `models/trip.dart` `reportId`) | dead code / compile error | delete; keep one HTTP path |
| 17 | Driver `availability` never set back to `AVAILABLE` after resolve | missing | do it in RESOLVE |

---

## 9. Build order (mirrors spec §22)

1. **Fix the client wedge** — remove the dead Supabase services and `flutter_map`-less leftovers so
   the app compiles and runs on one HTTP path.
2. **S0 + S1 + S9** — real session lifecycle: boot validation, sign-in, logout, `401` handling.
   Nothing else is trustworthy until the app stops trusting its own local file.
3. **S3** — approval states driven by backend truth and live events.
4. **S4** — duty dashboard: availability toggle, GPS uplink, nearby list, job cards, resume banner.
5. **S5** — accept race, including `409` and the `dispatch.accepted`-before-response case.
6. **S6** — real map, route, ETA, instructions, `START NAVIGATION`, status stepper, ARRIVED/RESOLVED.
7. **S8/S9 polish** — history fields, profile, permissions, notification plumbing.
8. **End-to-end pass** — one accident and one fire, two drivers racing, a cancellation, an app kill
   mid-trip, a rejected driver, a de-approved driver, and a route-provider outage. Every one of
   those must end in the correct screen with the correct server status.

---

## 10. Non-negotiable rules for this app

1. The backend decides everything security-relevant: approval, availability, eligibility, the
   accept winner, and every status transition.
2. Never render an unverified incident (§3) — Signal Aid only ever sees `VERIFIED` work.
3. Never fabricate ETA, distance, severity, or visual evidence (§19).
4. Never hand-roll routing (§10/§11) — use the routing provider.
5. Login once (§7) — restore silently, log out only on explicit action or security invalidation.
6. A driver who is not assigned to an emergency cannot touch it (§17).

---

## 11. Command Dashboard (admin console) — spec §15 coverage **[BUILT]**

The admin surface is the single page served at `/` from [`backend/public/index.html`](../backend/public/index.html).
It holds no business logic of its own: every panel reads an `/api/admin/*` endpoint and every action
posts to the backend, which re-checks the admin role before acting. Admin credentials are verified by
the backend (`POST /api/auth/admin/login`) — the page never decides who is an admin.

| §15 requirement | Where it lives | Backing endpoint |
|---|---|---|
| View users | Users view | `GET /api/admin/users` |
| View reported incidents | Incidents view | `GET /api/admin/incidents` |
| View incident status | Lifecycle badge on every incident row + lifecycle filter | `GET /api/admin/incidents` |
| Incident lifecycle is time-based (no manual approval) | TTL column + detail modal show expiry/retention; Resolve/Reject buttons removed | `GET /api/admin/incidents` (server TTL engine resolves at duration, purges 48h later) |
| View driver registration requests | Driver Approvals view | `GET /api/admin/driver-requests` |
| Approve drivers | Approve button | `POST /api/admin/driver-requests/:id/approve` |
| Reject drivers | Reject button (reason captured) | `POST /api/admin/driver-requests/:id/reject` |
| View approved emergency vehicles | Vehicles view | `GET /api/admin/drivers` |
| View active emergency requests | Assignments view | `GET /api/admin/dispatches` |
| View assigned drivers | Assigned Driver column on assignments and trips | `GET /api/admin/dispatches`, `GET /api/admin/trips` |
| Monitor emergency incidents | Stat cards + lifecycle badges + live socket refresh | `GET /api/admin/stats`, `GET /api/admin/incidents` |
| View driver locations where permitted | Vehicles view (coordinates + map link + last seen) | `GET /api/admin/drivers` |
| Manage vehicle availability | Availability select per vehicle | `PATCH /api/users/:id/availability` (admin-only) |
| Manage emergency assignments | Cancel / Release & re-dispatch per request | `PATCH /api/admin/dispatches/:id/status` |

### Root cause of the blank `—` trip columns

The Signal-Aid panel read `GET /api/trips`, which returns raw `emergency_trips` rows. The accept flow
inserted only `(id, dispatch_id, driver_id, vehicle_no, report_id, status)` — so `criticality`,
`travel_time` and `distance` were always `NULL` and the dashboard printed `—`.

Fixed at the source: `POST /api/dispatches/:id/accept` now writes

- `criticality` — the accepting driver's choice, else `high`,
- `distance` — haversine km from the driver's last known position to the incident.

Nothing is invented: a field stays `NULL` when the backend holds no evidence for it, and the panel
reads `GET /api/admin/trips` (joined to the incident and the driver) rather than the raw table.

### Verifying the console

`backend/scripts/e2e-admin-flow.sh` drives the whole workflow against a running server and prints the
exact payloads the dashboard consumes: report → `ACTIVE` → `DISPATCHED` immediately, driver
registration → pending → approved, first-to-accept wins (second attempt `409`), trip with
criticality/distance, `ARRIVED` → `RESOLVED`, driver released to `AVAILABLE`.
