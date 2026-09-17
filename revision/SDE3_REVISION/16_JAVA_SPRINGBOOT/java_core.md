# Java Core - SDE3 Must Know (Java 8, 11, 17, 21)

## Java 8 Features (Still Asked)

### Lambdas
```java
// Functional interface: one abstract method
Runnable r = () -> System.out.println("run");
Comparator<String> cmp = (a,b) -> a.length() - b.length();
```

### Streams
```java
List<String> list = Arrays.asList("a","bb","ccc");
list.stream()
  .filter(s -> s.length() > 1)
  .map(String::toUpperCase)
  .sorted()
  .collect(Collectors.toList());

// Important ops:
map, filter, flatMap, distinct, sorted, peek, limit, skip
forEach, collect, reduce, count, anyMatch, allMatch, findFirst

// Parallel stream: list.parallelStream() uses ForkJoinPool, careful for stateful
```

### Optional
```java
Optional<User> opt = userRepo.findById(id);
opt.ifPresent(u -> System.out.println(u));
User user = opt.orElse(new User());
User user2 = opt.orElseGet(() -> createDefault());
User user3 = opt.orElseThrow(() -> new NotFoundException());
opt.map(User::getEmail).filter(e -> e.contains("@")).orElse("default");

// Avoid: Optional as field or param, use only as return type
```

### Date/Time API (java.time)
```java
LocalDate date = LocalDate.now();
LocalTime time = LocalTime.now();
LocalDateTime dt = LocalDateTime.now();
ZonedDateTime zdt = ZonedDateTime.now(ZoneId.of("Asia/Kolkata"));
Instant instant = Instant.now();
Duration d = Duration.between(t1,t2);
Period p = Period.between(d1,d2);
DateTimeFormatter fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd");
```

### Default & Static Methods in Interface (Java 8)

## Java 11 Features

- var keyword (local variable type inference) - Java 10 actually
```java
var list = new ArrayList<String>(); // inferred
```
- String methods: isBlank, lines, strip, repeat
- Files.readString, writeString
- HttpClient new (replaces HttpURLConnection)
```java
HttpClient client = HttpClient.newHttpClient();
HttpRequest req = HttpRequest.newBuilder().uri(URI.create("https://api.com")).build();
HttpResponse<String> res = client.send(req, BodyHandlers.ofString());
```
- Running java file directly: `java Hello.java`

## Java 17 Features (LTS - Current Standard)

- Records (immutable data carrier)
```java
record User(String name, String email) {}
User u = new User("John","a@b.com");
u.name(); // accessor
```
- Sealed classes (restrict inheritance)
```java
sealed class Shape permits Circle, Rectangle {}
final class Circle extends Shape {}
final class Rectangle extends Shape {}
```
- Pattern matching for instanceof
```java
if (obj instanceof String s) { System.out.println(s.length()); } // no cast
```
- Text Blocks
```java
String json = """
  {
    "name": "John"
  }
  """;
```
- Switch expressions
```java
String day = switch (n) {
  case 1 -> "Mon";
  case 2 -> "Tue";
  default -> "Other";
};
```

## Java 21 Features (LTS Latest)

- Virtual Threads (Project Loom) - see concurrency file
- Pattern matching for switch
```java
switch (obj) {
  case String s -> System.out.println("String: "+s);
  case Integer i -> System.out.println("Int: "+i);
  case null -> System.out.println("null");
  default -> System.out.println("other");
}
```
- Record patterns
- Sequenced Collections (new interfaces: SequencedCollection, SequencedSet, SequencedMap with first/last/reversed)
- String Templates (preview)
- Scoped Values (preview, better than ThreadLocal for virtual threads)

## Important Java Concepts

### equals & hashCode Contract
- If equals true, hashCode must be same
- If hashCode same, equals may be false (collision)
- Always override both together, use Objects.equals and Objects.hash

### String, StringBuilder, StringBuffer

| String | StringBuilder | StringBuffer |
|--------|---------------|--------------|
| Immutable | Mutable | Mutable |
| Thread safe? No need immutable | Not thread safe | Thread safe synchronized |
| Pool | No | No |
| Use | Few changes | Many changes single thread | Many changes multi thread |

- String pool: `String s1 = "hello"` pooled, `new String("hello")` heap not pooled, `intern()` adds to pool

### Exception Handling

- Checked vs Unchecked
  - Checked: Compile time must handle (IOException, SQLException) - recoverable
  - Unchecked: RuntimeException (NullPointer, IllegalArgument) - programming errors
- Try-with-resources (AutoCloseable)
```java
try (FileReader fr = new FileReader("file")) { ... } // auto close
```
- Custom exception: Extend RuntimeException for unchecked

### Generics
- Type safety, erasure at runtime
- `List<String>` not `List<Object>`
- Wildcards: `? extends Animal` (upper bound, read), `? super Dog` (lower bound, write), PECS: Producer Extends Consumer Super

### Collections

| Collection | Impl | Ordering | Null | Thread Safe | Use |
|------------|------|----------|------|-------------|-----|
| List | ArrayList | Insertion | Yes | No | Random access fast |
| List | LinkedList | Insertion | Yes | No | Insert/delete fast |
| Set | HashSet | No | Yes 1 | No | Unique |
| Set | LinkedHashSet | Insertion | Yes | No | Unique + order |
| Set | TreeSet | Sorted | No | No | Sorted unique |
| Map | HashMap | No | Yes key 1 | No | Key-value fast |
| Map | LinkedHashMap | Insertion | Yes | No | LRU cache |
| Map | TreeMap | Sorted key | No | No | Sorted map |
| Queue | PriorityQueue | Priority | No | No | Heap |

- ArrayList vs LinkedList: ArrayList O(1) get, O(n) insert middle; LinkedList O(n) get, O(1) insert if iterator

### Fail-Fast vs Fail-Safe
- Fail-Fast: Throws ConcurrentModificationException if modified during iteration (HashMap, ArrayList)
- Fail-Safe: Copy or weakly consistent, no exception (ConcurrentHashMap, CopyOnWriteArrayList)

## Java 8 Interview Q

**Q: How HashMap works?**
- Array of buckets (Node[]), hash(key) -> index, bucket contains linked list (or tree if >8 entries Java 8+ to avoid DoS), equals to find, resize when load factor 0.75 exceeded, not thread safe

**Q: ConcurrentHashMap how works Java 8?**
- CAS for empty bucket, synchronized on first node of bucket if not empty, no segment locking like Java 7, better concurrency

**Q: Why String immutable?**
- Security (password), caching (pool), thread safety, class loading, hashCode caching

**Q: Difference between == and equals?**
- == reference comparison, equals content (overridden)
