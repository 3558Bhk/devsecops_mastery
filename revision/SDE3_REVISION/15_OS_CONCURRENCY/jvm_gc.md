# JVM Internals & Garbage Collection

## JVM Architecture

```
Java Code (.java) -> javac -> Bytecode (.class)
-> Class Loader -> JVM Memory -> Execution Engine (Interpreter + JIT) -> OS
```

### Class Loader
- Bootstrap (rt.jar), Extension, Application (classpath)
- Parent delegation model: Child delegates to parent first
- Custom class loader possible

### JVM Memory Areas

#### 1. Heap (Shared across threads)
- Stores objects, biggest area, GC happens here
- Divided:
  - Young Generation:
    - Eden (new objects)
    - Survivor S0, S1 (2 survivor spaces)
  - Old Generation (Tenured): Long-lived objects
  - (Java 8+ Metaspace replaced PermGen, not in heap but native memory)

#### 2. Stack (Per thread)
- Stores method calls, local variables, references
- LIFO, each method call creates stack frame
- StackOverflowError if recursion too deep

#### 3. Metaspace (Java 8+)
- Stores class metadata, methods, static variables (Java 7 PermGen had static)
- Native memory, not heap, auto grows with -XX:MaxMetaspaceSize

#### 4. PC Register (Per thread)
- Address of current executing instruction

#### 5. Native Method Stack
- For native methods (C/C++ via JNI)

## Garbage Collection

### What is GC?
- Automatic memory management, reclaims unreachable objects, no manual free like C++

### GC Roots (What is considered reachable?)
- Local variables in stack, active threads, static fields, JNI references

### Minor GC vs Major GC vs Full GC
- **Minor GC**: Young Gen collection, frequent, fast, stop-the-world brief
- **Major GC**: Old Gen collection, slower
- **Full GC**: Entire heap + metaspace, slowest, avoid

### Object Lifecycle
1. New object allocated in Eden
2. Minor GC: Surviving objects moved to S0, Eden cleared
3. Next Minor GC: Eden + S0 survivors -> S1, age increment
4. Age reaches threshold (default 15, -XX:MaxTenuringThreshold) -> promoted to Old Gen
5. Major GC cleans Old Gen when full

### GC Algorithms

#### 1. Serial GC
- Single thread, stop-the-world, for small apps, single core
- `-XX:+UseSerialGC`

#### 2. Parallel GC (Throughput Collector)
- Multiple threads for Young Gen, single for Old (or parallel old), high throughput, good for batch
- Default in Java 8
- `-XX:+UseParallelGC`

#### 3. CMS (Concurrent Mark Sweep) - Deprecated Java 9, removed Java 14
- Low pause, concurrent marking, but fragmentation, no compaction

#### 4. G1 GC (Garbage First) - Default Java 9+
- Divides heap into regions (1-32MB), tracks garbage, collects regions with most garbage first
- Low pause, predictable, compaction, concurrent
- `-XX:+UseG1GC`
- Good for large heap >4GB, balanced throughput & latency
- Humongous objects: >50% region size allocated directly in old gen

#### 5. ZGC (Z Garbage Collector) - Java 11 experimental, Java 15 prod, Java 21 generational
- Ultra low pause <1ms even for TB heaps, concurrent, colored pointers, load barriers
- `-XX:+UseZGC`
- Use: Very large heap, low latency required

#### 6. Shenandoah - Similar to ZGC, RedHat, low pause
- `-XX:+UseShenandoahGC`

### GC Tuning Flags

```bash
-Xms2g -Xmx4g # initial and max heap
-Xmn1g # young gen size
-XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200 # target pause
-XX:ParallelGCThreads=4
-XX:ConcGCThreads=2
-XX:+PrintGCDetails -Xlog:gc* # logs
-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp/dump.hprof
```

### How to Analyze GC Logs?
- Tools: GCViewer, GCEasy.io, VisualVM, JConsole, Java Mission Control
- Look for: Frequency of GC, pause times, promotion failures, full GC count

### OutOfMemoryError Types

- **Java heap space**: Heap full, leak or need bigger heap, analyze dump with Eclipse MAT
- **GC overhead limit exceeded**: GC spending 98% time reclaiming <2% heap, likely leak
- **Metaspace**: Too many classes loaded, e.g. dynamic proxy leak, increase MaxMetaspaceSize or fix leak
- **Unable to create new native thread**: Too many threads, OS limit, reduce thread pool or increase ulimit
- **Direct buffer memory**: NIO direct memory leak

### Memory Leak in Java?
- Yes, even with GC: Unintended references keep objects reachable
- Common: Static collection growing, listeners not removed, ThreadLocal not removed in pool, cache without eviction, unclosed resources (connection, stream)

### WeakReference, SoftReference, PhantomReference

- **Strong**: Default, `Object o = new Object()` never GCed while reachable
- **Soft**: GCed when memory low, good for cache `SoftReference<Cache>`
- **Weak**: GCed at next GC even if memory enough, `WeakHashMap` for canonicalizing, prevents leak
- **Phantom**: For cleanup tracking, enqueued after finalization, used with ReferenceQueue

### Finalize vs Cleaner
- finalize() deprecated Java 9, unreliable, performance issue
- Use try-with-resources AutoCloseable or Cleaner API

## JIT Compiler

- Interpreter slow, JIT compiles hot bytecode to native code for speed
- C1 (client) fast compile less optimization, C2 (server) slow compile high optimization, Tiered compilation uses both
- HotSpot detection: Method called many times -> JIT

## Interview Q

**Q: How to tune GC for low latency?**
- Use G1 or ZGC, set MaxGCPauseMillis, small young gen for frequent but short pauses, avoid humongous allocations, reuse objects, off-heap, profile with async-profiler

**Q: Difference stack vs heap?**
- Stack per thread small fast for primitives + refs, heap shared large for objects, GC

**Q: What is memory leak how to find?**
- Heap dump on OOM, analyze with MAT, look for largest retained objects, check static maps, thread locals, unclosed resources, use VisualVM, enable GC logs

**Q: Explain Java 21 virtual threads impact on GC?**
- Virtual threads many (millions) but stack is heap allocated not OS, GC handles, need to avoid pinning (synchronized blocks pin carrier thread, use ReentrantLock instead)
