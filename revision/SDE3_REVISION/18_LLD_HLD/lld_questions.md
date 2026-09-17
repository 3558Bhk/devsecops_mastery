# LLD (Low Level Design) - SDE3 Must Know

## LLD Process (Interview Steps)

1. **Requirements**: Functional + Non-functional, clarify, scope
2. **Use Cases & Actors**: Who uses? What actions?
3. **Class Diagram**: Identify nouns -> classes, verbs -> methods, relationships
4. **Schema**: If needed
5. **Design Patterns**: Which pattern fits?
6. **Code**: Write classes with SOLID, handle concurrency
7. **Edge Cases & Future Extensions**

## Common LLD Questions & Design

### 1. Parking Lot

**Requirements**: Multiple floors, different vehicle types (Bike, Car, Truck), different spot types, entry/exit gates, ticket, payment (cash, card), display board, price based on time

**Classes**:
- Vehicle (abstract) -> Bike, Car, Truck
- ParkingSpot (abstract) -> BikeSpot, CarSpot, TruckSpot, has Vehicle, isFree
- ParkingFloor has List<ParkingSpot>, display board
- ParkingLot (Singleton) has List<ParkingFloor>, List<Gate>
- Gate (abstract) -> EntryGate, ExitGate
- Ticket has entryTime, vehicle, spot, gate
- Payment (Strategy) -> Cash, Card, UPI
- PriceCalculator (Strategy based on vehicle type + duration)
- DisplayBoard

**Patterns**: Singleton (ParkingLot), Factory (Vehicle, Spot, Payment), Strategy (Pricing, Payment), Observer (DisplayBoard updates)

```java
class ParkingLot {
  private static ParkingLot instance;
  List<ParkingFloor> floors;
  private ParkingLot() {}
  public static synchronized ParkingLot getInstance() {
    if(instance==null) instance=new ParkingLot();
    return instance;
  }
  ParkingSpot findSpot(VehicleType type) { /* iterate floors */ }
}
```

### 2. Elevator System

**Requirements**: Multiple elevators, multiple floors, up/down buttons outside, floor buttons inside, scheduling algorithm

**Classes**: Elevator, Floor, Button (abstract) -> InsideButton, OutsideButton, Building has elevators + floors, Request, ElevatorController (Singleton), Scheduling Strategy (FCFS, SCAN, LOOK)

**Patterns**: State (Elevator states: Idle, MovingUp, MovingDown, DoorOpen), Observer, Strategy for scheduling, Singleton for controller

### 3. BookMyShow / Ticket Booking

**Requirements**: Multiple cities, theatres, screens, shows, movies, seats (different types), booking, payment, concurrency (no double booking)

**Classes**: City has Theatres, Theatre has Screens, Screen has Seats, Show has Movie + Screen + time, Seat (type, status), Booking has User + Show + Seats + status + payment, Movie, User

**Key Challenges**:
- Concurrency: Seat locking
  - Optimistic locking with @Version
  - Pessimistic: SELECT FOR UPDATE
  - Distributed lock: Redis lock with TTL
  - Temporary hold: Seat blocked for 10 min if not paid, then released via scheduler or delayed queue
- Payment: SAGA

**Patterns**: Factory (Seat), Strategy (Payment), Observer (Notification)

### 4. LRU Cache

**Requirements**: get O(1), put O(1), evict least recently used when full

**Design**: HashMap + Doubly Linked List
- Map key -> Node
- DLL maintains order: Most recent at head, least at tail
- get: If exists move to head, return value
- put: If exists update and move to head, else add to head, if size>capacity remove tail + map

```java
class LRUCache {
  class Node { int key,val; Node prev,next; }
  Map<Integer,Node> map;
  Node head,tail;
  int capacity;
  //...
}
```

### 5. Rate Limiter

**Requirements**: Limit requests per user/IP, e.g. 100 req/min

**Algorithms**:
- Fixed Window: Counter per window, simple but burst at boundary
- Sliding Window Log: Store timestamps, accurate but memory heavy
- Sliding Window Counter: Hybrid, fixed window + weighted previous window
- Token Bucket: Bucket with tokens refill at rate, each request consumes token, allows burst up to bucket size
- Leaky Bucket: Requests queued and processed at fixed rate, smooth

**Design**:
- For single server: In-memory map user -> bucket
- For distributed: Redis + Lua script for atomic
```java
// Token Bucket
class TokenBucket {
  long capacity, tokens;
  double refillRate; // tokens per sec
  long lastRefillTimestamp;
  synchronized boolean allowRequest() {
    refill();
    if(tokens>0) { tokens--; return true; }
    return false;
  }
  void refill() {
    long now=System.currentTimeMillis();
    long tokensToAdd = (long)((now-lastRefillTimestamp)/1000.0 * refillRate);
    tokens = Math.min(capacity, tokens+tokensToAdd);
    lastRefillTimestamp=now;
  }
}
```

### 6. Other LLD Questions to Prepare

- **Splitwise**: Users, groups, expenses, balances, settle up (min transactions via heap)
- **Tic-Tac-Toe**: Board, Player, Game, win conditions
- **Snake & Ladder**: Board, Dice, Player, Cell (Snake/Ladder)
- **ATM**: Card, Account, Bank, ATM states, dispense cash
- **Library Management**: Books, Members, Librarian, issue/return, fine
- **Inventory Management**: Products, warehouses, stock
- **Chat System**: Users, messages, groups, online status
- **Vending Machine**: State pattern, inventory, payment

## LLD Best Practices

1. SOLID principles
2. Use design patterns where appropriate, don't force
3. Handle concurrency (synchronized, locks, concurrent collections)
4. Use enums for types
5. Use interfaces for abstraction
6. Write clean code with proper naming
7. Consider extensibility: What if new vehicle type added? Should be easy
8. Thread-safe singleton
9. Use builder for complex objects
10. Document assumptions

## Interview Tips

- Start with requirements clarification (5 min)
- Draw class diagram on board (10 min) - show relationships: inheritance, composition, aggregation
- Explain patterns used (5 min)
- Code core classes (20 min) - don't code everything, focus on main flow + concurrency
- Discuss edge cases and extensions (5 min)
- Always mention thread safety for booking systems
