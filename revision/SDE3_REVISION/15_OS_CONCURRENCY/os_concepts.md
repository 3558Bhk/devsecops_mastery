# OS Concepts - SDE3 Quick Revision

## Process vs Thread

| Process | Thread |
|---------|--------|
| Independent program, own memory | Lightweight, shares process memory |
| Heavy, creation costly | Light, fast creation |
| Inter-process comm: IPC (pipe, socket) | Inter-thread comm: shared memory |
| Crash doesn't affect other process | Thread crash can kill process |
| Example: Chrome each tab process | Java threads inside JVM process |

- **Program**: Static code on disk
- **Process**: Running instance of program, has PCB (Process Control Block)
- **Thread**: Unit of execution within process

## Process States
- New -> Ready -> Running -> Waiting/Blocked -> Terminated
- Ready: Waiting for CPU
- Running: Using CPU
- Blocked: Waiting for IO

## Scheduling Algorithms
- **FCFS**: First Come First Serve, convoy effect
- **SJF**: Shortest Job First, optimal avg waiting but starvation
- **SRTF**: Preemptive SJF
- **Round Robin**: Time quantum, fair, used in OS
- **Priority**: Priority based, starvation possible, aging solves
- **Multilevel Queue**: Multiple queues with different priority

## Synchronization

### Race Condition
- Two threads access shared data concurrently, result depends on order
- Fix: Synchronization

### Critical Section
- Part of code accessing shared resource, only one thread at a time

### Mutex vs Semaphore

| Mutex | Semaphore |
|-------|-----------|
| Binary lock (0/1) | Counting, can be N |
| Ownership: Only owner can unlock | No ownership, any can signal |
| Use: Mutual exclusion | Use: Resource counting, signaling |
| Example: Lock bathroom | Example: 3 identical printers, count 3 |

### Deadlock
- 4 Coffman conditions must all hold:
1. Mutual Exclusion
2. Hold and Wait
3. No Preemption
4. Circular Wait

- **Prevention**: Break one condition (e.g. ordered locking to break circular wait)
- **Avoidance**: Banker's algorithm
- **Detection & Recovery**: Wait-for graph, kill process, preempt resource
- **Example**: Thread1 locks A waits B, Thread2 locks B waits A

```java
// Deadlock example
synchronized (lockA) {
  Thread.sleep(100);
  synchronized (lockB) { ... }
}
// Other thread opposite order lockB then lockA -> deadlock
// Fix: Always lock in same order
```

### Starvation vs Livelock
- Starvation: Low priority never gets CPU
- Livelock: Threads keep changing state but no progress (like two people in hallway both move side to side)

## Memory Management

### Virtual Memory
- OS gives each process illusion of large contiguous memory, maps virtual to physical via page table
- Benefits: Isolation, larger than RAM, efficient

### Paging
- Divide memory into fixed size pages (4KB), frames
- Page table maps virtual page to physical frame
- TLB (Translation Lookaside Buffer) caches page table for speed
- Page Fault: Page not in RAM, load from disk (slow)

### Segmentation
- Variable size segments based on logical division (code, data, stack)

### Thrashing
- Too many page faults, CPU spends more swapping than executing
- Fix: Increase RAM, reduce multiprogramming

## Inter-Process Communication (IPC)
- Pipe, Named Pipe, Shared Memory (fastest), Message Queue, Socket, Signals

## System Calls
- User mode -> Kernel mode via syscall (fork, exec, read, write, open)

## Fork vs Exec
- fork(): Creates copy of parent process
- exec(): Replaces current process with new program

## Zombie vs Orphan

| Zombie | Orphan |
|--------|--------|
| Child terminated but parent didn't call wait(), PCB still in table | Parent terminated before child, child adopted by init (PID 1) |
| Resource leak if many | Not leak, init will clean |

## Thread Types
- User threads (managed by user lib) vs Kernel threads (managed by OS)
- Many-to-One, One-to-One, Many-to-Many mapping

## Context Switching
- Save state of current process/thread and load next, overhead, cache pollution

## Important Commands (Linux)
```bash
ps -ef
top
htop
free -h
vmstat
iostat
lsof
strace -p PID # trace syscalls
```

## Interview Q: How does OS handle 10k connections?
- Traditional thread-per-connection doesn't scale (10k threads heavy)
- Use event-driven non-blocking IO: epoll (Linux), kqueue (macOS), IO multiplexing, Reactor pattern (Node.js, Nginx, Netty)
- C10K problem solved by Nginx, Node

## File System
- Inode stores metadata, directory maps name to inode
- Hard link same inode, soft link different inode pointing to path
