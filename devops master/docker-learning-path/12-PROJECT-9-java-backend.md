# PROJECT 9 · ☕ Java / Spring Boot Backend

> **Part of the Docker Learning Path.** Previous: [`11-PROJECT-8-react-frontend.md`](11-PROJECT-8-react-frontend.md) — Project 8 — React Frontend.
>
> 🎯 **Instructions & techniques:** multi-stage · `RUN --mount=type=cache` · Spring Boot layered jars · JVM container flags · non-root JVM
>
> 📚 **What you learn:** JDK vs JRE images, building with Maven inside Docker, the layered-jar caching win, JVM memory in a cgroup
>
> 🔁 **Every project here is written TWICE:**
> - **🔵 CASE 1 — a SIMPLE Dockerfile.** Easy to read, easy to get working, usually too big for production.
> - **🟢 CASE 2 — a MULTI-STAGE Dockerfile.** The production version: smaller, faster to rebuild, more secure, tests can fail the build.
>
> **Build Case 1 first**, run it, understand it — then build Case 2 and **measure the difference**. That comparison *is* the lesson.

---

# D.2 — PROJECT 9 · ☕ Java Backend (Spring Boot)

**🎯 What you learn:** JVM images (JDK vs JRE), building with Maven/Gradle inside a container, **Spring Boot layered jars** (the single biggest Java Docker optimisation), `.m2` cache mounts, non-root JVM, container-aware memory flags.

## 9.0 The app

```
09-java-backend/
├── pom.xml
├── Dockerfile              ← CASE 1 (simple)
├── Dockerfile.multistage   ← CASE 2
├── Dockerfile.gradle       ← CASE 2 variant for Gradle
├── .dockerignore
└── src/main/java/com/example/demo/
    ├── DemoApplication.java
    ├── TaskController.java
    ├── Task.java
    └── TaskService.java
```

### `pom.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.4.1</version>
    <relativePath/>
  </parent>

  <groupId>com.example</groupId>
  <artifactId>tasknest-java</artifactId>
  <version>1.0.0</version>
  <name>tasknest-java</name>

  <properties>
    <java.version>21</java.version>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <finalName>app</finalName>          <!-- → target/app.jar, a stable name -->
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
        <configuration>
          <layers><enabled>true</enabled></layers>   <!-- 🔑 enables the layered jar -->
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
```

### `src/main/java/com/example/demo/DemoApplication.java`

```java
package com.example.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DemoApplication {
    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }
}
```

### `src/main/java/com/example/demo/Task.java`

```java
package com.example.demo;

import java.time.Instant;
import java.util.List;

public record Task(
        long id,
        String title,
        String priority,
        List<String> tags,
        boolean done,
        Instant createdAt
) {}
```

### `src/main/java/com/example/demo/TaskService.java`

```java
package com.example.demo;

import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;

/** In-memory store, so this project has no external dependencies.
 *  Swap it for a JdbcTemplate/JPA repository in Project 10. */
@Service
public class TaskService {

    private final Map<Long, Task> tasks = new LinkedHashMap<>();
    private final AtomicLong seq = new AtomicLong(0);

    public TaskService() {
        create("Learn FROM, RUN and CMD", "high", List.of("docker", "basics"));
        create("Master ENTRYPOINT vs CMD", "medium", List.of("docker"));
        create("Build a multi-stage Java image", "high", List.of("docker", "java"));
    }

    public synchronized Task create(String title, String priority, List<String> tags) {
        long id = seq.incrementAndGet();
        Task t = new Task(id, title,
                priority == null ? "medium" : priority.toLowerCase(),
                tags == null ? List.of() : tags,
                false, Instant.now());
        tasks.put(id, t);
        return t;
    }

    public List<Task> list(String status, String priority) {
        return tasks.values().stream()
                .filter(t -> status == null
                        || ("done".equals(status) == t.done()))
                .filter(t -> priority == null || priority.equalsIgnoreCase(t.priority()))
                .sorted(Comparator.comparing(Task::done).thenComparing(Task::id).reversed())
                .toList();
    }

    public Optional<Task> get(long id) { return Optional.ofNullable(tasks.get(id)); }

    public Optional<Task> toggle(long id) {
        Task t = tasks.get(id);
        if (t == null) return Optional.empty();
        Task updated = new Task(t.id(), t.title(), t.priority(), t.tags(), !t.done(), t.createdAt());
        tasks.put(id, updated);
        return Optional.of(updated);
    }

    public boolean delete(long id) { return tasks.remove(id) != null; }

    public Map<String, Object> stats() {
        long total = tasks.size();
        long done  = tasks.values().stream().filter(Task::done).count();
        long high  = tasks.values().stream().filter(t -> !t.done() && "high".equals(t.priority())).count();
        return Map.of(
                "total", total,
                "done", done,
                "todo", total - done,
                "urgent_high", high,
                "completion_pct", total == 0 ? 0.0 : Math.round(done * 1000.0 / total) / 10.0
        );
    }
}
```

### `src/main/java/com/example/demo/TaskController.java`

```java
package com.example.demo;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.net.InetAddress;
import java.util.List;
import java.util.Map;

@RestController
@CrossOrigin(origins = "*")        // dev convenience; production uses an nginx proxy instead
public class TaskController {

    private final TaskService service;
    private final long started = System.currentTimeMillis();

    public TaskController(TaskService service) { this.service = service; }

    record TaskRequest(String title, String priority, List<String> tags) {}

    @GetMapping({"/", "/api/info"})
    public Map<String, Object> info() throws Exception {
        return Map.of(
                "service", "tasknest-java",
                "version", System.getProperty("app.version", "1.0.0"),
                "java", System.getProperty("java.version"),
                "hostname", InetAddress.getLocalHost().getHostName(),
                "pid", ProcessHandle.current().pid(),
                "uptime_seconds", (System.currentTimeMillis() - started) / 1000,
                "max_memory_mb", Runtime.getRuntime().maxMemory() / 1024 / 1024,
                "routes", List.of("/api/tasks", "/api/tasks/{id}", "/api/tasks/{id}/toggle",
                                   "/api/stats", "/api/health", "/api/ready",
                                   "/actuator/health")
        );
    }

    @GetMapping({"/api/health", "/health"})
    public Map<String, Object> health() {
        return Map.of("status", "ok", "uptime_seconds", (System.currentTimeMillis() - started) / 1000);
    }

    @GetMapping({"/api/ready", "/ready"})
    public Map<String, Object> ready() {
        return Map.of("ready", true, "checks", Map.of("database", true, "cache", true));
    }

    @GetMapping({"/api/tasks", "/tasks"})
    public Map<String, Object> list(@RequestParam(required = false) String status,
                                    @RequestParam(required = false) String priority) {
        return Map.of("source", "database", "tasks", service.list(status, priority));
    }

    @PostMapping({"/api/tasks", "/tasks"})
    public ResponseEntity<?> create(@RequestBody TaskRequest req) {
        if (req.title() == null || req.title().isBlank())
            return ResponseEntity.badRequest().body(Map.of("error", "'title' is required"));
        if (req.title().length() > 300)
            return ResponseEntity.badRequest().body(Map.of("error", "'title' must be <= 300 chars"));
        if (req.priority() != null && !List.of("low", "medium", "high").contains(req.priority().toLowerCase()))
            return ResponseEntity.badRequest().body(Map.of("error", "'priority' must be low|medium|high"));
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(service.create(req.title().trim(), req.priority(), req.tags()));
    }

    @GetMapping({"/api/tasks/{id}", "/tasks/{id}"})
    public ResponseEntity<?> get(@PathVariable long id) {
        return service.get(id)
                .map(t -> ResponseEntity.ok((Object) t))
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "task " + id + " not found")));
    }

    @PostMapping({"/api/tasks/{id}/toggle", "/tasks/{id}/toggle"})
    public ResponseEntity<?> toggle(@PathVariable long id) {
        return service.toggle(id)
                .map(t -> ResponseEntity.ok((Object) t))
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.of("error", "task " + id + " not found")));
    }

    @DeleteMapping({"/api/tasks/{id}", "/tasks/{id}"})
    public ResponseEntity<?> delete(@PathVariable long id) {
        return service.delete(id)
                ? ResponseEntity.ok(Map.of("deleted", id))
                : ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "task " + id + " not found"));
    }

    @GetMapping({"/api/stats", "/stats"})
    public Map<String, Object> stats() { return service.stats(); }
}
```

### `src/main/resources/application.properties`

```properties
# EVERYTHING from environment variables — Requirement 3 of the capstone
server.port=${PORT:8000}
server.address=0.0.0.0
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=20s
spring.application.name=tasknest-java

# Actuator: the JVM-native health endpoints
management.endpoints.web.exposure.include=health,info,metrics,prometheus
management.endpoint.health.probes.enabled=true
management.health.livenessState.enabled=true
management.health.readinessState.enabled=true

server.error.include-message=always
spring.jackson.serialization.write-dates-as-timestamps=false
logging.level.root=${LOG_LEVEL:INFO}
logging.pattern.console=%d{HH:mm:ss.SSS} %-5level [%thread] %logger{20} - %msg%n
```

### `.dockerignore`

```gitignore
target
**/target
build
**/build
.gradle
.git
.gitignore
.idea
*.iml
.vscode
.DS_Store
.env
*.env
Dockerfile*
docker-compose*.yml
.dockerignore
README.md
```

---

## 🔵 CASE 1 — the SIMPLE Dockerfile (build the jar on your host first)

```dockerfile
# ────────────────────────────────────────────────────────────
# CASE 1: SIMPLE. Assumes you already ran `mvn package` locally.
# Only a JRE ships — already better than shipping a JDK — but the
# build is NOT reproducible: it depends on YOUR local Maven/Java.
# ────────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# 🔑 JVM container flags — see the table below, these matter a lot
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+UseSerialGC -Djava.security.egd=file:/dev/./urandom"

COPY target/app.jar app.jar

# non-root: temurin images ship a 'root' user only, so create one
RUN addgroup -S -g 101 app && adduser -S -u 100 -G app -g 101 app \
 && chown -R app:app /app
USER app

EXPOSE 8000

HEALTHCHECK --interval=20s --timeout=3s --start-period=40s --retries=5 \
  CMD wget -q --spider http://127.0.0.1:8000/api/health || exit 1

# exec form via sh so $JAVA_OPTS expands, but `exec` keeps java as PID 1
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
```

```bash
cd 09-java-backend
mvn -DskipTests clean package            # or: ./mvnw -DskipTests clean package
docker build -t java-simple:v1 .
docker run -d --name java-simple -p 8000:8000 java-simple:v1
docker logs -f java-simple               # Spring Boot banner → "Started DemoApplication"
curl -s localhost:8000/api/info   | python3 -m json.tool
curl -s localhost:8000/api/tasks  | python3 -m json.tool
docker images java-simple:v1             # ~200 MB
docker rm -f java-simple
```

### 🔑 JVM-in-a-container flags you must know

| Flag | Why |
|---|---|
| `-XX:MaxRAMPercentage=75.0` | The JVM sees the **cgroup limit**, not the host RAM (since Java 10). Use a percentage, **never** `-Xmx512m` hard-coded — it breaks when you change the container limit. Leave 25% headroom for metaspace, threads and off-heap. |
| `-XX:+UseSerialGC` | For small heaps (< 2 GB) in containers, SerialGC uses far less memory than G1. Big win. |
| `-XX:InitialRAMPercentage=50.0` | Faster startup, less early GC churn. |
| `-Djava.security.egd=file:/dev/./urandom` | Avoids entropy-starvation stalls on startup in minimal images. |
| `-XX:+ExitOnOutOfMemoryError` | On OOM, exit immediately so the orchestrator restarts you, instead of limping along broken. |
| `--add-opens java.base/java.lang=ALL-UNNAMED` | Only if a library needs deep reflection. |
| `-XX:ActiveProcessorCount=N` | Force the JVM's CPU view if your cgroup quota confuses it. |

```bash
# prove the JVM respects the container limit:
docker run --rm -m 256m java-simple:v1 sh -c \
  'java -XX:MaxRAMPercentage=75 -XshowSettings:properties -version 2>&1 | head'
docker run -d -m 256m --name jlimit java-simple:v1 && docker stats --no-stream jlimit
```

---

## 🟢 CASE 2 — the MULTI-STAGE Dockerfile (build inside Docker, layered jar)

```dockerfile
# syntax=docker/dockerfile:1
# ────────────────────────────────────────────────────────────
# CASE 2: MULTI-STAGE.
#   stage 1  build with a full JDK + Maven (cached, discarded)
#   stage 2  test  (fails the build if tests fail)
#   stage 3  extract the Spring Boot LAYERED jar
#   stage 4  runtime: JRE only, 4 layers ordered by change frequency
# ────────────────────────────────────────────────────────────

ARG JDK_IMAGE=eclipse-temurin:21-jdk-alpine
ARG JRE_IMAGE=eclipse-temurin:21-jre-alpine

# ══════════════ STAGE 1: build ══════════════
FROM ${JDK_IMAGE} AS build
WORKDIR /workspace

# Copy the POM FIRST: dependencies are re-downloaded only when pom.xml changes.
# The cache mount keeps ~/.m2 between builds WITHOUT putting it in a layer.
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q dependency:go-offline

# Now the source (changes on every commit — cheap layer)
COPY src ./src

RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q -DskipTests clean package


# ══════════════ STAGE 2: test ══════════════
FROM build AS test
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q test
# A failure here ABORTS the build. Broken code never becomes an image.


# ══════════════ STAGE 3: extract the layered jar ══════════════
FROM build AS extract
WORKDIR /workspace
# `jarmode=layertools` splits app.jar into 4 directories by change frequency
RUN java -Djarmode=layertools -jar target/app.jar extract
RUN ls -la /workspace   # dependencies/ spring-boot-loader/ snapshot-dependencies/ application/


# ══════════════ STAGE 4: runtime ══════════════
FROM ${JRE_IMAGE} AS runtime

ARG APP_VERSION=1.0.0
ARG GIT_COMMIT=unknown

ENV APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT} \
    PORT=8000 \
    LOG_LEVEL=INFO \
    JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0 -XX:+UseSerialGC -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom"

LABEL org.opencontainers.image.title="tasknest-java" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}"

WORKDIR /app

RUN addgroup -S -g 101 app && adduser -S -u 100 -G app -g 101 app \
 && mkdir -p /app/data && chown -R app:app /app

# 🔑 ORDERED BY CHANGE FREQUENCY — this is the whole point of layered jars.
#    dependencies (50 MB, change monthly)  ← cached for weeks
#    spring-boot-loader (tiny, changes with the Boot version)
#    snapshot-dependencies (rarely present)
#    application (your classes, ~50 KB)    ← the ONLY layer that changes per commit
COPY --from=extract --chown=app:app /workspace/dependencies/           ./
COPY --from=extract --chown=app:app /workspace/spring-boot-loader/     ./
COPY --from=extract --chown=app:app /workspace/snapshot-dependencies/  ./
COPY --from=extract --chown=app:app /workspace/application/            ./

USER app
EXPOSE 8000
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=20s --timeout=3s --start-period=45s --retries=5 \
  CMD wget -q --spider http://127.0.0.1:8000/actuator/health/liveness || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -Dapp.version=$APP_VERSION org.springframework.boot.loader.launch.JarLauncher"]
```

> 📌 Spring Boot **3.2+** moved the launcher to `org.springframework.boot.loader.launch.JarLauncher`.
> Spring Boot **2.x / 3.0–3.1** uses `org.springframework.boot.loader.JarLauncher`. Match your version.

### Build & verify

```bash
docker build -f Dockerfile.multistage \
  --build-arg APP_VERSION=1.0.0 \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo local) \
  -t java-multi:v1 .

docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep java-
#   java-simple   v1   ~200 MB
#   java-multi    v1   ~195 MB   (similar total — the win is CACHING, not size)

docker run -d --name jm -p 8000:8000 java-multi:v1
docker logs -f jm
curl -s localhost:8000/api/info  | python3 -m json.tool
curl -s localhost:8000/api/tasks | python3 -m json.tool
curl -s localhost:8000/actuator/health | python3 -m json.tool
docker exec jm whoami            # app
docker exec jm sh -c 'which mvn javac 2>&1'   # NOT FOUND ✅
docker history java-multi:v1 --human --format "table {{.Size}}\t{{.CreatedBy}}" | head -12
docker rm -f jm
```

### 🔬 THE layered-jar caching experiment (this is the real lesson)

```bash
# build #1 — cold
time docker build -f Dockerfile.multistage -t java-multi:v1 .        # ~2-4 minutes

# build #2 — nothing changed
time docker build -f Dockerfile.multistage -t java-multi:v1 .        # ~2 SECONDS (all CACHED)

# change ONE line of Java source, rebuild
sed -i 's/tasknest-java/tasknest-java-EDITED/' src/main/java/com/example/demo/TaskController.java
time docker build -f Dockerfile.multistage -t java-multi:v2 .
# → dependency:go-offline  CACHED
# → mvn package            re-runs (fast, deps are in the cache mount)
# → COPY dependencies/     CACHED   ← the 50 MB layer is NOT re-pushed! 🎯
# → COPY application/      re-runs  (~50 KB)

# now change pom.xml — everything below rebuilds
```

**Why this matters:** without layering, `COPY target/app.jar` is **one 60 MB layer** invalidated by every single commit → every push/pull/deploy transfers 60 MB. With layering, a code change transfers **~50 KB**. In CI with 30 deploys a day, that's the difference between minutes and hours of registry traffic.

### `Dockerfile.gradle` (Gradle variant of Case 2)

```dockerfile
# syntax=docker/dockerfile:1
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /workspace
# Copy ONLY the wrapper + build files first → dependency layer stays cached
COPY gradlew settings.gradle.kts build.gradle.kts ./
COPY gradle ./gradle
RUN --mount=type=cache,target=/root/.gradle ./gradlew --no-daemon dependencies || true
COPY src ./src
RUN --mount=type=cache,target=/root/.gradle ./gradlew --no-daemon clean build

FROM eclipse-temurin:21-jdk-alpine AS extract
WORKDIR /workspace
COPY --from=build /workspace/build/libs/*-SNAPSHOT.jar app.jar
RUN java -Djarmode=layertools -jar app.jar extract

FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app
RUN addgroup -S app && adduser -S -G app app
COPY --from=extract --chown=app:app /workspace/dependencies/ ./
COPY --from=extract --chown=app:app /workspace/spring-boot-loader/ ./
COPY --from=extract --chown=app:app /workspace/snapshot-dependencies/ ./
COPY --from=extract --chown=app:app /workspace/application/ ./
USER app
EXPOSE 8000
ENTRYPOINT ["java","org.springframework.boot.loader.launch.JarLauncher"]
```

### Go even smaller (optional)

| Approach | Size | Trade-off |
|---|---|---|
| `eclipse-temurin:21-jre-alpine` | ~195 MB | the sensible default |
| `eclipse-temurin:21-jre-jammy` | ~265 MB | glibc, better compatibility |
| `gcr.io/distroless/java21-debian12` | ~230 MB | no shell, no package manager — very secure, hard to debug |
| **jlink custom runtime** | ~90 MB | strips unused JDK modules; needs `--add-modules` tuning |
| **GraalVM native image** | ~55 MB, **starts in 60 ms** | AOT compiled; long build, reflection needs config |
| **CRaC** (Coordinated Restore at Checkpoint) | ~200 MB | snapshot/restore in < 1 s |

```dockerfile
# jlink example — a runtime containing ONLY the modules your app uses
FROM eclipse-temurin:21-jdk-alpine AS jlink
RUN jlink --add-modules java.base,java.logging,java.sql,java.naming,java.management,jdk.unsupported \
    --strip-debug --no-header-files --no-man-pages --compress=2 \
    --output /jre

FROM alpine:3.22
COPY --from=jlink /jre /opt/java
ENV PATH="/opt/java/bin:$PATH"
COPY --from=extract /workspace/application/ /app/
CMD ["java","-jar","/app/app.jar"]
```

---

## 🔨 Tasks for Project 9

> **9.1** Build both cases. Run `docker history` on each and count the layers. Which layer is biggest in each? Explain why Case 1's biggest layer can never be cached across code changes, while Case 2's can.

> **9.2** Prove the build is reproducible. Delete your local `target/` folder and your entire `~/.m2` repository, then build Case 2 — it must succeed with no host Java installed at all. Now try the same with Case 1. Write down what that proves.

> **9.3** Make the tests gate the build. Add `src/test/java/com/example/demo/TaskServiceTest.java` with a test that asserts `create()` returns an incrementing id and `toggle()` flips `done`. Build Case 2 → passes. Then break the assertion and rebuild → confirm **no image is produced**.

> **9.4** Memory-limit the JVM correctly. Run with `-m 256m` and `-m 1g`, and inside each run:
> ```bash
> docker exec <c> sh -c 'java -XshowSettings:properties -version 2>&1 | grep -i "max heap"'
> curl -s localhost:8000/api/info | grep max_memory_mb
> ```
> Confirm the heap scales with the container limit without changing the image. Then set `JAVA_OPTS="-Xmx2g"` and run with `-m 256m` — what happens and why?

> **9.5** Go rootless and read-only.
> ```bash
> docker run -d --name jlocked -p 8000:8000 -m 384m \
>   --read-only --tmpfs /tmp --tmpfs /app/data \
>   --cap-drop ALL --security-opt no-new-privileges:true \
>   --user 100:101 java-multi:v1
> curl -s localhost:8000/api/health
> ```
> If Spring fails to write somewhere, find out where from the logs and add a `tmpfs` for it. Document every writable path you had to allow.

> **9.6 (bonus)** Add a GraalVM native-image stage and compare **startup time**:
> ```bash
> time docker run --rm java-multi:v1 sh -c 'java -jar /app/app.jar & sleep 0.1'
> ```
> vs a native image. Record cold-start milliseconds for both. Why does this matter for serverless / autoscaling?

<details>
<summary>👉 Answers</summary>

**9.1** Case 1's biggest layer is `COPY target/app.jar` (~60 MB) — a **single opaque blob**, so any code change invalidates all 60 MB. Case 2's biggest is `COPY --from=extract /workspace/dependencies/` (~50 MB) — but that layer's *content* only changes when `pom.xml` changes, so it stays `CACHED` across ordinary commits and is never re-pushed. Your code lands in a separate ~50 KB layer.

**9.2** Case 2 succeeds with zero host Java/Maven: the **JDK, Maven and every dependency live inside the build stage**. That's what "reproducible build" means — any machine with Docker produces a bit-identical image. Case 1 fails immediately (`target/app.jar` doesn't exist), because it depends on your laptop's exact JDK version, Maven version, settings.xml and local repository. This is the "works on my machine" problem Docker exists to kill.

**9.3** A failing `mvn test` exits non-zero → `RUN` fails → **the build aborts and no tag is created**. Verify with `docker images | grep java-multi` (nothing new). This is the cheapest possible CI gate, and it runs in the *exact* environment you ship.

**9.4** With `MaxRAMPercentage=75`, `-m 256m` gives a ~192 MB heap and `-m 1g` gives ~768 MB — **same image, different limit**. The JVM reads the cgroup memory limit (Java 10+ container awareness). With `-Xmx2g` and `-m 256m` the JVM happily reserves a 2 GB heap plan, the cgroup kills it at 256 MB → **exit code 137, `OOMKilled=true`**, often with no Java OutOfMemoryError at all (the *kernel* killed it, not the JVM). This is the single most common Java-in-Docker production incident. **Rule: always use `MaxRAMPercentage`, never `-Xmx`, and leave ≥25% headroom for metaspace + threads + off-heap + code cache.**

**9.5** Typical writable paths Spring needs: `/tmp` (Tomcat work dir, JIT hsperfdata), and `/app/data` if you persist anything. If it fails with `Unable to create tempDir` or `hs_err_pid*.log`, add the matching `--tmpfs`. Note `--read-only` also blocks `/app/logs`, which is *why* the app logs to **stdout** (`logging.pattern.console`) rather than files — a 12-factor requirement that Docker makes natural.

**9.6** JVM+Spring Boot cold start ≈ **2–6 s**; GraalVM native ≈ **50–150 ms**. That's a 20–50× improvement, which matters enormously for: Kubernetes scale-from-zero, Knative/Cloud Run, AWS Lambda, and CI test parallelism where you boot the app hundreds of times. Costs: a 5–15 minute build, no JIT peak-throughput advantage (native is usually ~10–20% slower under sustained load), and reflection/proxies need `reflect-config.json` hints (Spring AOT generates most of them).
</details>

---

---

## ➡️ Next

**[`13-PROJECT-10-react-java-fullstack.md`](13-PROJECT-10-react-java-fullstack.md)** — Project 10.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
