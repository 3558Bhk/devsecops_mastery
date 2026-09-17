# Multithreading & Concurrency - SDE3 Java Focus

## Why Multithreading?
- Better CPU utilization, responsiveness, throughput
- Example: Web server handles many requests concurrently

## Thread Lifecycle (Java)
- New -> Runnable -> Running -> Blocked/Waiting/Timed Waiting -> Terminated
- `thread.start()` -> Runnable, not immediately Running (scheduler decides)
- `wait()`, `sleep()`, `join()`, `park()`

## Creating Threads

```java
// 1. Extend Thread
class MyThread extends Thread { public void run() { System.out.println("run"); } }
new MyThread().start();

// 2. Implement Runnable (preferred)
Runnable r = () -> System.out.println("run");
new Thread(r).start();

// 3. Callable + Future (returns result)
Callable<Integer> c = () -> 42;
FutureTask<Integer> ft = new FutureTask<>(c);
new Thread(ft).start();
ft.get();

// 4. ExecutorService (best practice)
ExecutorService executor = Executors.newFixedThreadPool(10);
executor.submit(() -> System.out.println("task"));
executor.shutdown();
```

## Executor Framework

```java
// Types
Executors.newFixedThreadPool(10) // fixed 10 threads
Executors.newCachedThreadPool() // creates as needed, 60 sec idle timeout, risk OOM
Executors.newSingleThreadExecutor() // one thread
Executors.newScheduledThreadPool(5) // scheduled tasks
Executors.newWorkStealingPool() // ForkJoinPool, work stealing

// Custom ThreadPoolExecutor (Recommended for prod)
ThreadPoolExecutor executor = new ThreadPoolExecutor(
  10, // core pool size
  20, // max pool size
  60L, TimeUnit.SECONDS, // keep alive
  new LinkedBlockingQueue<>(100), // work queue
  new CustomThreadFactory(),
  new ThreadPoolExecutor.CallerRunsPolicy() // rejection policy
);

// Rejection Policies:
// AbortPolicy (default) throws RejectedExecutionException
// CallerRunsPolicy runs in caller thread
// DiscardPolicy discards silently
// DiscardOldestPolicy discards oldest queued
```

## Synchronization

### synchronized
- Intrinsic lock (monitor), reentrant, one lock per object
```java
synchronized (this) { /* critical */ }
synchronized method: locks this for instance method, Class object for static

// Pros: Simple, auto release
// Cons: No timeout, no interrupt, single condition, not fair
```

### volatile
- Guarantees visibility (writes visible to other threads immediately), not atomicity
- Prevents instruction reordering
- Use: Flag to stop thread `volatile boolean stop = false;`
- Not use: `volatile count++` not atomic, need synchronized or AtomicInteger

### Atomic Classes
- CAS (Compare And Swap) non-blocking, lock-free
- AtomicInteger, AtomicLong, AtomicReference, AtomicBoolean
```java
AtomicInteger counter = new AtomicInteger(0);
counter.incrementAndGet(); // atomic, no synchronized needed
```

### Locks (java.util.concurrent.locks)
```java
ReentrantLock lock = new ReentrantLock();
lock.lock();
try {
  // critical
} finally { lock.unlock(); }

// Features over synchronized:
// tryLock with timeout
// lockInterruptibly
// fair lock (FIFO)
// multiple conditions
// isLocked, getQueueLength

ReentrantReadWriteLock rwLock = new ReentrantReadWriteLock();
// Read lock shared many readers, Write lock exclusive
// Use: Read heavy cache
```

### CountDownLatch vs CyclicBarrier vs Semaphore vs Phaser

| Tool | Use | Reusable? | Example |
|------|-----|-----------|---------|
| **CountDownLatch** | Wait for N tasks to complete, one-time | No | Main waits for 3 services to start |
| **CyclicBarrier** | N threads wait for each other at barrier, then proceed together, reusable | Yes | 4 threads process chunks then merge |
| **Semaphore** | Limit concurrent access to resource, permits | Yes | Only 3 threads can access DB connection pool |
| **Phaser** | More flexible barrier, dynamic parties | Yes | Advanced |

```java
// CountDownLatch
CountDownLatch latch = new CountDownLatch(3);
executor.submit(() -> { doWork(); latch.countDown(); });
latch.await(); // wait

// CyclicBarrier
CyclicBarrier barrier = new CyclicBarrier(3, () -> System.out.println("All reached, merging"));
executor.submit(() -> { work(); barrier.await(); });

// Semaphore
Semaphore sem = new Semaphore(3);
sem.acquire(); // if permits available decrement else block
try { useResource(); } finally { sem.release(); }
```

## Concurrent Collections

- **ConcurrentHashMap**: Segment locking (Java 7) / CAS + synchronized bucket (Java 8+), better than Collections.synchronizedMap, iterators weakly consistent, no ConcurrentModificationException
- **CopyOnWriteArrayList**: Copy on write, good for read heavy, event listeners
- **BlockingQueue**: ArrayBlockingQueue, LinkedBlockingQueue, PriorityBlockingQueue, SynchronousQueue, DelayQueue - used for producer-consumer
```java
BlockingQueue<Task> queue = new LinkedBlockingQueue<>(100);
queue.put(task); // blocks if full
Task t = queue.take(); // blocks if empty
```

## ThreadLocal
- Each thread has own copy of variable
- Use: SimpleDateFormat (not thread safe) per thread, user context, transaction
- Risk: Memory leak in thread pools if not removed (thread reused)
```java
ThreadLocal<User> userHolder = new ThreadLocal<>();
userHolder.set(user);
try { ... } finally { userHolder.remove(); } // must remove in pool
```

## CompletableFuture (Async Programming)

```java
CompletableFuture.supplyAsync(() -> fetchUser(123))
  .thenApply(user -> fetchOrders(user.getId()))
  .thenApply(orders -> calculateTotal(orders))
  .thenAccept(total -> System.out.println(total))
  .exceptionally(ex -> { System.err.println(ex); return null; });

// Combine
CompletableFuture<User> f1 = supplyAsync(() -> fetchUser());
CompletableFuture<Order> f2 = supplyAsync(() -> fetchOrder());
f1.thenCombine(f2, (user, order) -> user + order).thenAccept(System.out::println);

// All of
CompletableFuture.allOf(f1, f2, f3).join();
```

## Problems & Solutions

### Deadlock Prevention
- Lock ordering: Always acquire locks in same order
- TryLock with timeout
- Deadlock detection via thread dump `jstack PID`

### Race Condition
- Synchronize, atomic, immutable objects

### Visibility
- volatile, synchronized, final

### Thread Starvation
- Fair lock, increase priority

## Virtual Threads (Java 21 - Project Loom) - SDE3 Must Know 2025-26

- Traditional platform threads: 1 OS thread per Java thread, heavy (1MB stack), limited ~few thousand
- Virtual threads: Lightweight, managed by JVM, not OS, millions possible, cheap
- Blocking virtual thread doesn't block OS thread, carrier thread reused
- How: `Thread.startVirtualThread(() -> ...)` or `Executors.newVirtualThreadPerTaskExecutor()`
- Benefits: Write synchronous blocking code but get async scalability, no need for reactive complex
- Use: High throughput IO-bound (web servers), replaces reactive for many cases
- Example:
```java
// Before: Need reactive or thread pool limited
// After Java 21:
try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
  for (int i=0; i<1_000_000; i++) {
    executor.submit(() -> handleRequest());
  }
}
// Can handle 1M concurrent tasks!

// Spring Boot 3.2+ supports virtual threads
// spring.threads.virtual.enabled=true
```

## Interview Q

**Q: How to create thread-safe Singleton?**
- Enum or double-checked locking volatile

**Q: synchronized vs ReentrantLock?**
- synchronized simple auto release, ReentrantLock flexible with timeout, interrupt, fairness, multiple conditions, but need manual unlock in finally

**Q: How to avoid deadlock?**
- Lock ordering, tryLock timeout, deadlock detection

**Q: Explain CompletableFuture vs Future?**
- Future blocking get(), no chaining, no exception handling. CompletableFuture non-blocking chaining thenApply, combine, async.

**Q: What is ThreadPool size formula?**
- CPU-bound: N_cpu + 1
- IO-bound: N_cpu * (1 + wait_time/compute_time) e.g. 2*N_cpu or more, or use virtual threads
