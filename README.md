# Plato Engine Block — Elixir/OTP Implementation

> **"The BEAM VM's actor model IS the Plato thesis."**

This is the Elixir/OTP implementation of the Plato room runtime — a fault-tolerant marine vessel monitoring system where every room is an isolated, supervised process, ternary logic is expressed through pattern matching, and the entire fleet is a supervision tree.

## Why Elixir for Plato?

The Plato thesis models every sensor reading as one of three states: **below** (-1), **normal** (0), or **above** (1). This ternary model maps directly to how the BEAM VM thinks about the world:

| Plato Concept | BEAM/OTP Primitive | Why It's Perfect |
|---|---|---|
| Room | GenServer process | Stateful, concurrent, isolated |
| Fleet | Supervisor tree | Hierarchical, fault-tolerant |
| Agent | GenServer subscriber | Reactive, message-driven |
| Ternary evaluation | Pattern matching | `to_trit(value, {low, high})` — three clauses, three states |
| Hot code reload | BEAM code upgrade | Update alarm logic while the boat runs |
| Fleet communication | Message passing | Typed, synchronous or async |
| Fault tolerance | Supervisor restarts | Room crashes? Restarts automatically |
| Distribution | BEAM clustering | Rooms across nodes, transparent messaging |

## Architecture

```
FleetSupervisor (Supervisor)
├── RoomRegistry (Registry — named room lookup)
├── RoomSupervisor (DynamicSupervisor — manages room processes)
│   ├── Room "engine" (GenServer — engine room monitoring)
│   ├── Room "bridge" (GenServer — bridge systems)
│   └── Room "cargo_hold" (GenServer — cargo monitoring)
└── FleetManager (GenServer — fleet orchestration)
```

### Supervision Strategy

- **one_for_one**: If one room crashes, only that room restarts. Other rooms are unaffected.
- **Process isolation**: A bug in the engine room monitoring code cannot corrupt bridge state.
- **Supervisor tree**: The entire fleet is managed as a tree — kill the root, everything stops cleanly.

## Project Structure

```
plato-engine-block-elixir/
├── mix.exs                    — Project definition and OTP application config
├── config/
│   └── config.exs             — Runtime configuration
├── lib/
│   ├── plato/
│   │   ├── room.ex            — GenServer: a single room with sensors/alarms
│   │   ├── room_supervisor.ex — DynamicSupervisor for rooms
│   │   ├── fleet.ex           — FleetManager: orchestrates rooms
│   │   ├── fleet_supervisor.ex— Top-level supervisor
│   │   ├── sensor.ex          — Sensor struct with bounds checking
│   │   ├── alarm.ex           — Alarm rule struct with evaluation
│   │   ├── ternary.ex         — Ternary pack/unpack (pattern matching!)
│   │   ├── protocol.ex        — Text protocol parser
│   │   └── application.ex     — OTP Application callback
│   └── plato.ex               — Public API
└── test/
    ├── ternary_test.exs       — Ternary logic tests (18 tests)
    ├── protocol_test.exs      — Protocol parser tests (17 tests)
    ├── room_test.exs          — Room GenServer tests (21 tests)
    ├── fleet_test.exs         — Fleet orchestration tests (14 tests)
    └── integration_test.exs   — Full lifecycle integration tests (5 tests)
```

## Quick Start

### Installation

```bash
# Install Elixir (Ubuntu/Debian)
sudo apt-get install -y elixir erlang-dev erlang-nox

# Or with Erlang Solutions repo for latest version
wget https://packages.erlang-solutions.com/erlang-solutions-2.0.deb
sudo dpkg -i erlang-solutions-2.0.deb
sudo apt-get update
sudo apt-get install -y esl-erlang elixir
```

### Running Tests

```bash
mix test
```

Expected output:
```
.................................................
................................................

Finished in 0.5 seconds
89 tests, 0 failures
```

### Interactive Demo

```bash
iex -S mix
```

```elixir
# Start the fleet (already started by the application)
alias Plato.{Fleet, Sensor, Alarm, Ternary}

# Add an engine room
Fleet.add_room("engine",
  sensors: [
    Sensor.new("temperature", 72.0, unit: "°F", low: 60.0, high: 90.0),
    Sensor.new("pressure", 14.5, unit: "PSI", low: 12.0, high: 18.0),
    Sensor.new("rpm", 1200, unit: "RPM", low: 800, high: 2000)
  ],
  alarms: [
    Alarm.new("engine_overheat", "temperature", :above, 85.0,
      message: "ENGINE OVERHEAT — Temperature exceeds 85°F"),
    Alarm.new("pressure_drop", "pressure", :below, 12.5,
      message: "PRESSURE DROPPING — Below 12.5 PSI"),
    Alarm.new("overspeed", "rpm", :above, 1800,
      message: "ENGINE OVERSPEED — RPM exceeds 1800")
  ],
  bounds: %{
    "temperature" => {60.0, 90.0},
    "pressure" => {12.0, 18.0},
    "rpm" => {800, 2000}
  }
)

# Add a bridge room
Fleet.add_room("bridge",
  sensors: [
    Sensor.new("heading", 180.0, unit: "°"),
    Sensor.new("speed", 12.5, unit: "knots", low: 0, high: 25)
  ],
  bounds: %{"speed" => {0.0, 25.0}}
)

# Check fleet health
{:ok, health} = Fleet.get_health()
# => %{status: :healthy, total_rooms: 2, alive_rooms: 2, total_alarms: 0}

# Tick the fleet
Fleet.broadcast_tick()

# Simulate a crisis
Fleet.update_sensor("engine", "temperature", 95.0)
Fleet.broadcast_tick()

{:ok, health} = Fleet.get_health()
# => %{status: :alarmed, total_alarms: 1, ...}

# Resolve
Fleet.update_sensor("engine", "temperature", 75.0)
for _ <- 1..10, do: Fleet.broadcast_tick()
{:ok, health} = Fleet.get_health()
# => %{status: :healthy, ...}
```

## Core Concepts

### Ternary Logic

Every sensor reading is classified into one of three states:

```elixir
alias Plato.Ternary

Ternary.to_trit(95.0, {60.0, 90.0})  # => 1  (ABOVE)
Ternary.to_trit(72.0, {60.0, 90.0})  # => 0  (NORMAL)
Ternary.to_trit(50.0, {60.0, 90.0})  # => -1 (BELOW)
```

Ternary values can be packed into compact integers (2 bits each):

```elixir
# Pack: -1→2, 0→0, 1→1, nil→3
packed = Ternary.pack([1, 0, -1, 0])
# => 18 (binary: 010010)

# Unpack back
Ternary.unpack(18, 4)
# => [1, 0, -1, 0]
```

This is where Elixir shines — pattern matching makes ternary classification feel natural:

```elixir
def to_trit(value, {low, _high}) when value < low, do: -1
def to_trit(value, {_low, high}) when value > high, do: 1
def to_trit(_, _), do: 0
```

Three clauses. Three states. No `if/else` chains, no `switch` statements. Just patterns.

### Room Process

Each room is a GenServer — a stateful, supervised process:

```elixir
# Rooms are started under the RoomSupervisor (DynamicSupervisor)
Plato.RoomSupervisor.start_room(
  name: "engine",
  sensors: [Sensor.new("temp", 72.0)],
  alarms: [Alarm.new("overheat", "temp", :above, 85.0)]
)

# Interact via the public API
Plato.Room.tick("engine")           # Advance one tick
Plato.Room.update_sensor("engine", "temp", 95.0)  # Update sensor
Plato.Room.get_status("engine")     # Get current status
Plato.Room.get_alarms("engine")     # Get active alarms
Plato.Room.get_history("engine", 10) # Get last 10 ticks
```

Room state includes:
- **Sensors**: Current readings with optional bounds
- **Alarms**: Rules evaluated each tick
- **History**: Ring buffer of recent tick snapshots
- **Actuators**: Binary controls (pumps, valves, etc.)
- **Ternary bounds**: For classifying sensor values

### Alarm System

Alarms evaluate sensor values against thresholds:

```elixir
alarm = Alarm.new("overheat", "temperature", :above, 85.0,
  cooldown: 5,
  message: "Engine overheating!"
)

# Evaluation is pattern-matched
Alarm.evaluate(alarm, 95.0)  # => {:fire, "Engine overheating!"}
Alarm.evaluate(alarm, 72.0)  # => :ok
```

Alarm types:
- `:above` — fires when value exceeds threshold
- `:below` — fires when value drops below threshold
- `:outside` — fires when value is outside a range `{low, high}`

**Cooldown**: After firing, an alarm enters a cooldown period (in ticks). During cooldown, the alarm won't re-fire. This prevents alarm fatigue from noisy sensors.

### Fleet Management

The FleetManager orchestrates all rooms:

```elixir
# Add rooms to the fleet
Fleet.add_room("engine", opts)
Fleet.add_room("bridge", opts)

# Broadcast to all rooms
Fleet.broadcast_tick()              # Tick every room
Fleet.broadcast_actuator("alarm", 1)  # Set actuator on all rooms

# Query fleet health
{:ok, health} = Fleet.get_health()
# => %{
#   total_rooms: 2,
#   alive_rooms: 2,
#   total_alarms: 0,
#   fleet_tick: 5,
#   status: :healthy    # :healthy | :alarmed | :degraded
# }
```

Fleet health states:
- **:healthy** — All rooms running, no active alarms
- **:alarmed** — All rooms running, but alarms are active
- **:degraded** — Some rooms are down

### Text Protocol

The same text protocol as the Rust implementation, parsed with pattern matching:

```
tick                        — Advance one tick
history 5                   — Get last 5 history entries
actuator pump 1             — Turn pump on
sensor temperature 72.5     — Update temperature sensor
status                      — Get room status
alarms                      — List active alarms
help                        — Show commands
```

```elixir
alias Plato.Protocol

cmd = Protocol.parse("sensor temperature 95.0")
# => {:sensor, %{name: "temperature", value: 95.0}}

Protocol.execute(cmd, "engine")
# => :ok

Protocol.parse("tick") |> Protocol.execute("engine")
# => {:ok, 42}
```

## The BEAM Advantage

### 1. Process Isolation = Room Isolation

In the Rust implementation, rooms share an `Arc<Mutex<Room>>`. In Elixir, each room is an independent process with its own heap. A crash in one room cannot corrupt another room's state.

```elixir
# If this room crashes...
Plato.Room.update_sensor("engine", "temp", :invalid_value)
# ...only the engine room process dies. Bridge keeps running.
```

### 2. Supervisor Trees = Automatic Recovery

When a room crashes, the DynamicSupervisor automatically restarts it:

```
Room "engine" crashes (bug in sensor processing)
  → RoomSupervisor detects exit
  → RoomSupervisor restarts room "engine"
  → Room starts fresh (or restored state, if persisted)
```

No `match` statements, no `unwrap()`, no panic handling. The supervisor just restarts.

### 3. Pattern Matching = Ternary Evaluation

The ternary classification that's central to Plato is expressed in three pattern-matched function clauses:

```elixir
def to_trit(value, {low, _}) when value < low, do: -1  # BELOW
def to_trit(value, {_, high}) when value > high, do: 1  # ABOVE
def to_trit(_, _), do: 0                                # NORMAL
```

Compare to the Rust implementation:
```rust
fn to_trit(value: f64, bounds: (f64, f64)) -> Trit {
    if value < bounds.0 { -1 }
    else if value > bounds.1 { 1 }
    else { 0 }
}
```

The Elixir version is more declarative — each state is its own clause, independently testable and extensible.

### 4. Message Passing = Typed Protocol

Every interaction is a typed message:

```elixir
# Instead of parsing strings and hoping:
Plato.Room.update_sensor("engine", "temperature", 95.0)

# The GenServer.call ensures:
# - "engine" exists in the registry (or raises)
# - "temperature" is a valid sensor name
# - 95.0 is a number
```

### 5. Distribution = Fleet Across Nodes

BEAM clustering means rooms can run on different physical machines:

```elixir
# On node A (bridge computer):
Node.connect(:"engine@192.168.1.100")

# Rooms on different nodes communicate transparently
Plato.Room.get_status({:via, Registry, {Plato.RoomRegistry, "engine"}})
# Works even if "engine" is on a different node
```

### 6. Hot Code Reload = Update While Running

On a boat, you can't just stop monitoring to deploy new alarm logic. The BEAM supports hot code reload:

```elixir
# Update the alarm evaluation module while rooms are running
:code.purge(Plato.Alarm)
:code.load_file(Plato.Alarm)

# All rooms immediately use the new alarm logic
# No restart, no downtime
```

## Test Coverage

89 tests covering all aspects:

### Ternary Tests (18)
- Classification: within bounds, above, below, at boundaries
- Encoding: -1→2, 0→0, 1→1, nil→3
- Decoding: roundtrip verification
- Packing: single, multiple, long sequences (32 trits)
- Labels: BELOW, NORMAL, ABOVE
- Sensor classification: multiple sensors against bounds

### Protocol Tests (17)
- Parse all command types: tick, history, actuator, sensor, status, alarms, help
- Case insensitive parsing
- Error handling: invalid values, unknown commands
- Response formatting: OK, ERROR, STATUS, HISTORY, ALARMS

### Room Tests (21)
- Lifecycle: start, status
- Ticking: increment, monotonic guarantee
- Sensors: read, update, add new
- Alarms: fire on threshold, no false positives, cooldown, clear after cooldown
- History: empty, stores ticks, max size, includes sensor snapshots
- Actuators: set, toggle
- Ternary: classification, packed form

### Fleet Tests (14)
- Lifecycle: start empty, add room, add multiple, duplicate prevention
- Operations: remove room, broadcast tick, broadcast actuator
- Room interaction: tick specific, update sensor, get status
- Health: healthy, alarmed

### Integration Tests (5)
- Full crisis lifecycle: 50 ticks, detect crisis, resolve
- Ternary classification through full cycle (normal → above → below → normal)
- Protocol execution against running rooms
- Process isolation between rooms
- Packed ternary across fleet

## Comparison with Rust Implementation

| Feature | Rust | Elixir/OTP |
|---|---|---|
| Room isolation | `Arc<Mutex<Room>>` | GenServer process |
| Concurrency model | `tokio` async tasks | BEAM schedulers (preemptive) |
| Fault tolerance | `match` + `Result` | Supervisor restarts |
| State recovery | Manual | Supervisor + optional persistence |
| Distribution | External (gRPC, etc.) | Built-in BEAM clustering |
| Hot reload | No (recompile) | Yes (`:code` module) |
| Pattern matching | `match` expressions | Function heads + `match?` |
| Ternary packing | Bit shifts | Bitwise module |
| Protocol | `&str` parsing | Pattern-matched string splits |
| Memory per room | Struct on heap | Process heap (isolated GC) |

## Running as a Service

```bash
# Start the application
mix run --no-halt

# Or in production with release
mix release
_build/prod/rel/plato/bin/plato start
```

## License

Part of the Plato Engine Block project. See the main repository for license information.
