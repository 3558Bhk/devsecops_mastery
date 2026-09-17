# ☕ Project 9 — Java / Spring Boot Backend on Kubernetes

> **Time:** 2.5 hours · **Prereq:** [Project 2](05-PROJECT-2-deployment-service.md), [Project 3](06-PROJECT-3-config-secrets.md)
>
> - 🔵 **CASE 1 — Simple.** One Dockerfile, one Deployment, one Service. Working in 20 minutes.
> - 🟢 **CASE 2 — Production.** Layered multi-stage build, JVM container awareness, Actuator probes, graceful shutdown, HPA, PDB, NetworkPolicy, metrics, and the memory math that stops OOMKills.
>
> **The single biggest Java-on-Kubernetes problem** is memory: the JVM sees the container limit and *still* gets OOMKilled, because heap is only ~60% of a JVM's footprint. §9.7 fixes that permanently.

---

## 9.0 The app

A small Spring Boot 3 REST API. If you don't want to write it, use any Spring Boot app you have — the Kubernetes parts are identical.

```bash
mkdir -p ~/k8s-learn/p9 && cd ~/k8s-learn/p9
# generate at https://start.spring.io with: Java 21, Maven, dependencies =
#   Spring Web, Spring Boot Actuator, Spring Data JPA, PostgreSQL Driver,
#   Micrometer Prometheus Registry, Validation, Lombok
# or:
curl https://start.spring.io/starter.zip \
  -d type=maven-project -d language=java -d bootVersion=3.4.1 \
  -d baseDir=shop-api -d groupId=com.harish -d artifactId=shop-api \
  -d name=shop-api -d packageName=com.harish.shop \
  -d javaVersion=21 \
  -d dependencies=web,actuator,data-jpa,postgresql,micrometer-registry-prometheus,validation \
  -o shop-api.zip && unzip shop-api.zip && rm shop-api.zip
cd shop-api
```

`src/main/java/com/harish/shop/Product.java`:

```java
package com.harish.shop;

import jakarta.persistence.*;
import jakarta.validation.constraints.*;

@Entity
@Table(name = "products")
public class Product {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @NotBlank @Size(max = 120)
    private String name;

    @NotNull @PositiveOrZero
    private Double price;

    @Column(length = 2000)
    private String description;

    public Product() {}
    public Product(String name, Double price, String description) {
        this.name = name; this.price = price; this.description = description;
    }
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String n) { this.name = n; }
    public Double getPrice() { return price; }
    public void setPrice(Double p) { this.price = p; }
    public String getDescription() { return description; }
    public void setDescription(String d) { this.description = d; }
}
```

`src/main/java/com/harish/shop/ProductRepository.java`:

```java
package com.harish.shop;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface ProductRepository extends JpaRepository<Product, Long> {
    List<Product> findByNameContainingIgnoreCase(String fragment);
}
```

`src/main/java/com/harish/shop/ProductController.java`:

```java
package com.harish.shop;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.net.InetAddress;
import java.time.Duration;
import java.util.*;

@RestController
@RequestMapping("/api/products")
public class ProductController {

    private static final Logger log = LoggerFactory.getLogger(ProductController.class);

    private final ProductRepository repo;
    private final Counter createdCounter;
    private final Timer listTimer;
    private final String podName;
    private final String version;

    public ProductController(ProductRepository repo,
                             MeterRegistry registry,
                             @Value("${POD_NAME:local}") String podName,
                             @Value("${app.version:dev}") String version) {
        this.repo = repo;
        this.podName = podName;
        this.version = version;
        this.createdCounter = Counter.builder("shop.products.created")
                .description("Products created")
                .tag("pod", podName).tag("version", version)
                .register(registry);
        this.listTimer = Timer.builder("shop.products.list.duration")
                .description("Time to list products")
                .publishPercentiles(0.5, 0.95, 0.99)
                .publishPercentileHistogram()
                .serviceLevelObjectives(Duration.ofMillis(50), Duration.ofMillis(200), Duration.ofSeconds(1))
                .tag("pod", podName).tag("version", version)
                .register(registry);
    }

    @GetMapping
    public List<Product> list(@RequestParam(required = false) String q) {
        return listTimer.record(() -> {
            List<Product> result = (q == null || q.isBlank())
                    ? repo.findAll()
                    : repo.findByNameContainingIgnoreCase(q);
            log.info("list products q={} count={}", q, result.size());
            return result;
        });
    }

    @GetMapping("/{id}")
    public Product get(@PathVariable Long id) {
        return repo.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "product " + id + " not found"));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Product create(@Valid @RequestBody Product p) {
        Product saved = repo.save(p);
        createdCounter.increment();
        log.info("created product id={} name={}", saved.getId(), saved.getName());
        return saved;
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        if (!repo.existsById(id)) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "product " + id);
        repo.deleteById(id);
        log.warn("deleted product id={}", id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/slow")
    public List<Product> slow() throws InterruptedException {
        Thread.sleep(3000);           // for testing timeouts and HPA
        return repo.findAll();
    }
}
```

`src/main/java/com/harish/shop/HealthController.java`:

```java
package com.harish.shop;

import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
public class HealthController {

    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
            "service", "shop-api",
            "version", System.getenv().getOrDefault("APP_VERSION", "dev"),
            "pod", System.getenv().getOrDefault("POD_NAME", "local")
        );
    }

    /** Deliberate failure switch — for testing probes, rollbacks and alerts. */
    @GetMapping("/api/chaos/{what}")
    public String chaos(@PathVariable String what) {
        switch (what) {
            case "liveness":   LivenessToggle.dead = true;  return "liveness will now fail";
            case "readiness":  ReadinessToggle.dead = true; return "readiness will now fail";
            case "recover":    LivenessToggle.dead = false; ReadinessToggle.dead = false; return "recovered";
            case "oom": {
                List<byte[]> leak = new ArrayList<>();
                while (true) leak.add(new byte[10 * 1024 * 1024]);   // never returns
            }
            case "crash":      Runtime.getRuntime().halt(137);        return "unreachable";
            default:           return "unknown: " + what;
        }
    }
}

class LivenessToggle  { static volatile boolean dead = false; }
class ReadinessToggle { static volatile boolean dead = false; }
```

`src/main/resources/application.yaml`:

```yaml
server:
  port: 8080
  shutdown: graceful                       # ⭐ drain in-flight requests on SIGTERM
  compression:
    enabled: true
    mime-types: application/json,text/plain
    min-response-size: 1024
  error:
    include-stacktrace: never              # never leak stack traces to clients
    include-message: never

spring:
  application:
    name: shop-api
  lifecycle:
    timeout-per-shutdown-phase: 25s        # must be < terminationGracePeriodSeconds - preStop
  datasource:
    url: ${SPRING_DATASOURCE_URL:jdbc:postgresql://db:5432/app}
    username: ${SPRING_DATASOURCE_USERNAME:postgres}
    password: ${SPRING_DATASOURCE_PASSWORD:postgres}
    hikari:
      maximum-pool-size: ${DB_POOL_SIZE:10}
      minimum-idle: 2
      connection-timeout: 3000
      validation-timeout: 2000
      pool-name: shop-pool
  jpa:
    hibernate:
      ddl-auto: validate                   # NEVER `update` in prod — use Flyway/Liquibase
    open-in-view: false                    # ⭐ avoid the lazy-loading-in-view anti-pattern
    properties:
      hibernate.jdbc.batch_size: 30
      hibernate.order_inserts: true

management:
  endpoints:
    web:
      base-path: /actuator
      exposure:
        include: health,info,prometheus,metrics,env,loggers,threaddump,heapdump
  endpoint:
    health:
      show-details: when_authorized
      show-components: always
      probes:
        enabled: true                      # ⭐ exposes /actuator/health/liveness and /readiness
      group:
        readiness:
          include: readinessState,db,redis
        liveness:
          include: livenessState           # ⭐ ONLY the app itself — no dependencies!
  health:
    livenessstate: {enabled: true}
    readinessstate: {enabled: true}
  prometheus:
    metrics:
      export:
        enabled: true
  metrics:
    tags:
      application: ${spring.application.name}
      version: ${app.version:dev}
    distribution:
      percentiles-histogram:
        http.server.requests: true
      slo:
        http.server.requests: 50ms,100ms,200ms,500ms,1s
  tracing:
    sampling:
      probability: 0.1

logging:
  level:
    root: INFO
    com.harish.shop: ${LOG_LEVEL_APP:INFO}
    org.hibernate.SQL: ${LOG_LEVEL_SQL:WARN}
  pattern:
    console: "%d{yyyy-MM-dd'T'HH:mm:ss.SSSXXX} %-5level [${POD_NAME:local}] [%thread] %logger{36} - %msg%n"

app:
  version: ${APP_VERSION:dev}
```

`pom.xml` — add these two plugins:

```xml
<build>
  <plugins>
    <plugin>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-maven-plugin</artifactId>
      <configuration>
        <!-- ⭐ enables `java -Djarmode=tools -jar app.jar extract --layers` -->
        <layers><enabled>true</enabled></layers>
      </configuration>
    </plugin>
  </plugins>
</build>
```

`src/test/java/com/harish/shop/ShopApiApplicationTests.java`:

```java
package com.harish.shop;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest
@TestPropertySource(properties = {
    "spring.datasource.url=jdbc:h2:mem:test",
    "spring.jpa.hibernate.ddl-auto=create-drop"
})
class ShopApiApplicationTests {
    @Test void contextLoads() {}
}
```

Build it:

```bash
./mvnw -q clean package -DskipTests
ls -lh target/*.jar
# -rw-r--r-- 1 harish harish 42M  shop-api-0.0.1-SNAPSHOT.jar
```

---

# 🔵 CASE 1 — Simple (20 minutes)

## 9.1 The simple Dockerfile

`Dockerfile`:

```dockerfile
FROM eclipse-temurin:21-jdk-alpine
WORKDIR /app
COPY target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

```bash
docker build -t shop-api:case1 .
docker images shop-api:case1
# shop-api   case1   ...   480MB        ← JDK + jar, running as root, no probes
kind load docker-image shop-api:case1 --name learn
```

Test it standalone first (always — isolate Docker problems from Kubernetes problems):

```bash
docker run --rm -p 8080:8080 shop-api:case1 &
sleep 25
curl -s localhost:8080/actuator/health
curl -s localhost:8080/api/products
kill %1
```

> If it fails here, it will fail in Kubernetes too, and you'll waste an hour blaming the cluster.

## 9.2 A database to talk to

`k8s/db.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata: {name: pg-creds}
stringData:
  username: shop
  password: "L3arn-K8s!"
  database: app
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: db}
spec:
  replicas: 1
  selector: {matchLabels: {app: db}}
  strategy: {type: Recreate}
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
        - name: postgres
          image: postgres:17-alpine
          ports: [{containerPort: 5432, name: postgres}]
          env:
            - {name: POSTGRES_USER,     valueFrom: {secretKeyRef: {name: pg-creds, key: username}}}
            - {name: POSTGRES_PASSWORD, valueFrom: {secretKeyRef: {name: pg-creds, key: password}}}
            - {name: POSTGRES_DB,       valueFrom: {secretKeyRef: {name: pg-creds, key: database}}}
            - {name: PGDATA,            value: /var/lib/postgresql/data/pgdata}
          readinessProbe:
            exec: {command: ["sh","-c","pg_isready -U $POSTGRES_USER -d $POSTGRES_DB -h 127.0.0.1"]}
            periodSeconds: 5
            failureThreshold: 12
          resources:
            requests: {cpu: 200m, memory: 256Mi}
            limits:   {cpu: "1",   memory: 1Gi}
          volumeMounts: [{name: data, mountPath: /var/lib/postgresql/data}]
      volumes:
        - name: data
          persistentVolumeClaim: {claimName: pg-data}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: pg-data}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 2Gi}}
---
apiVersion: v1
kind: Service
metadata: {name: db}
spec:
  selector: {app: db}
  ports: [{name: postgres, port: 5432}]
```

```bash
kubectl apply -f k8s/db.yaml
kubectl rollout status deploy/db
kubectl get pvc pg-data
```

## 9.3 The simple manifests

`k8s/simple.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  labels: {app: shop-api}
spec:
  replicas: 2
  selector: {matchLabels: {app: shop-api}}
  template:
    metadata: {labels: {app: shop-api}}
    spec:
      containers:
        - name: api
          image: shop-api:case1
          imagePullPolicy: IfNotPresent
          ports: [{name: http, containerPort: 8080}]
          env:
            - {name: SPRING_DATASOURCE_URL,      value: "jdbc:postgresql://db:5432/app"}
            - {name: SPRING_DATASOURCE_USERNAME, valueFrom: {secretKeyRef: {name: pg-creds, key: username}}}
            - {name: SPRING_DATASOURCE_PASSWORD, valueFrom: {secretKeyRef: {name: pg-creds, key: password}}}
            - {name: SPRING_JPA_HIBERNATE_DDL_AUTO, value: "update"}   # ⚠️ Case 1 shortcut
          readinessProbe:
            httpGet: {path: /actuator/health/readiness, port: http}
            initialDelaySeconds: 30          # ⚠️ a guess — Case 2 does this properly
            periodSeconds: 10
          livenessProbe:
            httpGet: {path: /actuator/health/liveness, port: http}
            initialDelaySeconds: 60
            periodSeconds: 20
          resources:
            requests: {cpu: 250m, memory: 512Mi}
            limits:   {cpu: "1",   memory: 1Gi}
---
apiVersion: v1
kind: Service
metadata: {name: shop-api}
spec:
  selector: {app: shop-api}
  ports: [{name: http, port: 8080, targetPort: http}]
```

```bash
kubectl apply -f k8s/simple.yaml
kubectl rollout status deploy/shop-api --timeout=180s
kubectl get pods -l app=shop-api -o wide
kubectl logs deploy/shop-api --tail=30
```

Test:

```bash
kubectl port-forward svc/shop-api 8080:8080 &
sleep 2
curl -s localhost:8080/actuator/health | jq .
curl -s localhost:8080/api/products | jq .
curl -s -XPOST localhost:8080/api/products -H 'Content-Type: application/json' \
  -d '{"name":"Widget","price":9.99,"description":"A widget"}' | jq .
curl -s localhost:8080/api/products | jq .
curl -s localhost:8080/actuator/prometheus | grep -E '^shop_products|^jvm_memory_used' | head -10
kill %1
```

## 9.4 What's wrong with Case 1

| Problem | Impact |
|---|---|
| **JDK** in the runtime image | 480 MB; you only need the JRE (~200 MB) or jlink (~60 MB) |
| `COPY target/*.jar` | Every code change re-copies the whole 42 MB fat jar → no layer caching, slow builds, slow pulls |
| `initialDelaySeconds: 30/60` | A guess. Too short = killed during startup; too long = slow failure detection |
| `ddl-auto: update` | Hibernate mutates your schema on boot. **Never in production** — use Flyway |
| No JVM memory flags | The JVM guesses; you'll get OOMKilled or waste half your limit |
| Runs as root | Container escape = root on the node |
| No `server.shutdown: graceful` wiring to the Pod | Requests dropped on every deploy |
| No metrics scraping, no HPA, no PDB | Invisible and fragile |
| No security context | Fails any policy scan |

```bash
kubectl delete -f k8s/simple.yaml
```

---

# 🟢 CASE 2 — Production (2 hours)

## 9.5 The layered multi-stage Dockerfile

Spring Boot fat jars have a **layered** structure exactly for this reason: dependencies change rarely, your code changes constantly. Separate them and Docker caches the 40 MB of libraries forever.

`Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1
# ═══════════════════════════════════════════════════════════════
# STAGE 1 — build. Maven + JDK. Thrown away at the end.
# ═══════════════════════════════════════════════════════════════
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /build

# ── dependency layer: cached until a pom changes ──
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2/repository \
    mvn -B -q dependency:go-offline

# ── source layer ──
COPY src ./src
RUN --mount=type=cache,target=/root/.m2/repository \
    mvn -B -q clean package -DskipTests \
 && cp target/*.jar /build/app.jar

# ═══════════════════════════════════════════════════════════════
# STAGE 2 — split the jar into Spring Boot's layers
# ═══════════════════════════════════════════════════════════════
FROM eclipse-temurin:21-jre-alpine AS extract
WORKDIR /extract
COPY --from=build /build/app.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --destination /extract/layered
# produces: dependencies/  spring-boot-loader/  snapshot-dependencies/  application/

# ═══════════════════════════════════════════════════════════════
# STAGE 3 — runtime. JRE only, non-root, layered.
# ═══════════════════════════════════════════════════════════════
FROM eclipse-temurin:21-jre-alpine AS runtime

# tini = proper PID 1 (signal forwarding + zombie reaping)
RUN apk add --no-cache tini curl \
 && addgroup -g 10001 spring \
 && adduser  -u 10001 -G spring -S -D spring \
 && mkdir -p /app /tmp /app/logs \
 && chown -R spring:spring /app /tmp

WORKDIR /app

# ── layers, in order of least → most frequently changing ──
COPY --from=extract --chown=spring:spring /extract/layered/dependencies/          ./
COPY --from=extract --chown=spring:spring /extract/layered/spring-boot-loader/    ./
COPY --from=extract --chown=spring:spring /extract/layered/snapshot-dependencies/ ./
COPY --from=extract --chown=spring:spring /extract/layered/application/           ./

USER 10001:10001
EXPOSE 8080

# ── JVM container flags. See §9.7 for the reasoning. ──
ENV JAVA_OPTS="-XX:MaxRAMPercentage=70.0 \
               -XX:InitialRAMPercentage=50.0 \
               -XX:+UseG1GC \
               -XX:MaxGCPauseMillis=100 \
               -XX:+ExitOnOutOfMemoryError \
               -XX:+HeapDumpOnOutOfMemoryError \
               -XX:HeapDumpPath=/tmp \
               -Djava.security.egd=file:/dev/./urandom \
               -Dfile.encoding=UTF-8 \
               -Duser.timezone=UTC \
               -Djava.io.tmpdir=/tmp"

# Spring Boot 3.2+ launcher class. For 3.0/3.1 use:
#   org.springframework.boot.loader.JarLauncher   (no ".launch")
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh", "-c", "exec java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]

# ── build-time metadata (OCI labels) ──
ARG GIT_SHA=unknown
ARG BUILD_TIME=unknown
LABEL org.opencontainers.image.title="shop-api" \
      org.opencontainers.image.description="Shop REST API (Spring Boot)" \
      org.opencontainers.image.vendor="Harish Kumar Brahmandam" \
      org.opencontainers.image.source="https://github.com/3558Bhk/shop-api" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_TIME}" \
      org.opencontainers.image.licenses="MIT"
```

```bash
docker build \
  --build-arg GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo dev) \
  --build-arg BUILD_TIME=$(date -u +%FT%TZ) \
  -t shop-api:case2 .

docker images | grep shop-api
# shop-api   case1   ...   480MB
# shop-api   case2   ...   238MB       ← JRE only

# Prove the layer caching works: change one line of code and rebuild
touch src/main/java/com/harish/shop/ProductController.java
docker build -t shop-api:case2b . 2>&1 | grep -E 'CACHED|DONE'
# the dependencies layers are CACHED — only the `application/` layer rebuilds
```

### 🪶 CASE 2-extreme — jlink: a custom runtime, ~90 MB

If your app doesn't use reflection-heavy libraries that need every JDK module:

```dockerfile
FROM eclipse-temurin:21-jdk-alpine AS jlink
RUN jlink \
      --add-modules java.base,java.logging,java.sql,java.naming,java.management,java.instrument,java.security.jgss,java.desktop,java.scripting,jdk.unsupported,jdk.crypto.ec,jdk.zipfs,jdk.naming.dns \
      --strip-debug --no-man-pages --no-header-files \
      --compress=zip-6 \
      --output /jre
# test it: /jre/bin/java -version

FROM alpine:3.22 AS runtime
RUN apk add --no-cache tini curl && addgroup -g 10001 spring && adduser -u 10001 -G spring -S -D spring
COPY --from=jlink /jre /opt/java
COPY --from=extract --chown=spring:spring /extract/layered/ /app/
ENV PATH=/opt/java/bin:$PATH JAVA_HOME=/opt/java
USER 10001
WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["/sbin/tini","--"]
CMD ["java","-XX:MaxRAMPercentage=70","org.springframework.boot.loader.launch.JarLauncher"]
```

```bash
docker images | grep shop-api
# shop-api   jlink   ...   94MB        ← 5× smaller than Case 1
```

Trade-off: if you hit `NoClassDefFoundError: java/xml/...`, add the module to `--add-modules`. Discover them with:

```bash
jdeps --ignore-missing-deps --print-module-deps target/*.jar
```

### Even smaller: Spring Native / GraalVM (native image)

```bash
./mvnw -Pnative native:compile -DskipTests     # takes 5-15 minutes, needs lots of RAM
```

| | JVM | Native |
|---|---|---|
| Image size | ~240 MB | ~90 MB |
| Startup | 8–25 s | **50–150 ms** |
| Memory | 400–800 MB | 80–150 MB |
| Peak throughput | Higher | ~10–20% lower |
| Build time | 30 s | 5–15 min |
| Reflection/proxies | Just works | Needs `reflect-config.json` hints |

**Native is the right choice for:** serverless / scale-to-zero, high-density clusters, fast-autoscaling workloads, CLI tools.
**JVM is the right choice for:** long-running high-throughput services, apps heavy on reflection/CGLIB/dynamic proxies, teams without time for native-image hint debugging.

---

## 9.6 The production manifests

`k8s/config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: shop-api-config
  namespace: shop
  labels: {app: shop-api}
data:
  # Spring reads these as SPRING_* env vars → relaxed binding into properties
  SPRING_PROFILES_ACTIVE: "prod"
  SPRING_DATASOURCE_URL: "jdbc:postgresql://db.shop.svc.cluster.local:5432/app"
  SPRING_JPA_HIBERNATE_DDL_AUTO: "validate"
  SPRING_JPA_OPEN_IN_VIEW: "false"
  DB_POOL_SIZE: "10"
  LOG_LEVEL_APP: "INFO"
  LOG_LEVEL_SQL: "WARN"
  MANAGEMENT_METRICS_TAGS_ENVIRONMENT: "prod"
---
# JVM tuning that ops may want to change without a rebuild
apiVersion: v1
kind: ConfigMap
metadata:
  name: shop-api-jvm
  namespace: shop
data:
  JAVA_OPTS: >-
    -XX:MaxRAMPercentage=70.0
    -XX:InitialRAMPercentage=50.0
    -XX:+UseG1GC
    -XX:MaxGCPauseMillis=100
    -XX:+ExitOnOutOfMemoryError
    -XX:+HeapDumpOnOutOfMemoryError
    -XX:HeapDumpPath=/tmp
    -XX:+UseStringDeduplication
    -Djava.security.egd=file:/dev/./urandom
    -Dfile.encoding=UTF-8
    -Duser.timezone=UTC
---
apiVersion: v1
kind: Secret
metadata: {name: db-creds, namespace: shop}
stringData:
  username: shop
  password: "L3arn-K8s!-pr0d"
```

`k8s/deployment.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: shop-api, namespace: shop}
automountServiceAccountToken: false       # the API doesn't talk to the K8s API
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  namespace: shop
  labels:
    app: shop-api
    app.kubernetes.io/name: shop-api
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: shop
spec:
  replicas: 3
  revisionHistoryLimit: 8
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  selector:
    matchLabels: {app: shop-api}
  template:
    metadata:
      labels: {app: shop-api, version: v1}
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/actuator/prometheus"
        checksum/config: REPLACE_ME        # CI fills this; forces a rollout on config change
    spec:
      serviceAccountName: shop-api
      terminationGracePeriodSeconds: 60     # ⭐ > preStop(10) + spring shutdown(25) + margin

      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile: {type: RuntimeDefault}

      # ── spread across zones and nodes ──
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: {matchLabels: {app: shop-api}}
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector: {matchLabels: {app: shop-api}}
                topologyKey: kubernetes.io/hostname

      # ── ⭐ wait for the DB to be reachable before the JVM even starts ──
      initContainers:
        - name: wait-for-db
          image: busybox:1.37
          command:
            - sh
            - -c
            - |
              echo "waiting for db.shop.svc.cluster.local:5432"
              i=0
              until nc -z db.shop.svc.cluster.local 5432; do
                i=$((i+1))
                [ $i -gt 60 ] && { echo "TIMEOUT: db never came up"; exit 1; }
                sleep 2
              done
              echo "db is reachable"
          resources: {requests: {cpu: 10m, memory: 8Mi}, limits: {cpu: 100m, memory: 32Mi}}

      containers:
        - name: api
          image: ghcr.io/3558bhk/shop-api:1.0.0    # ⭐ pinned
          imagePullPolicy: IfNotPresent
          ports:
            - {name: http,    containerPort: 8080}
            - {name: metrics, containerPort: 8080}

          securityContext:
            allowPrivilegeEscalation: false
            privileged: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}

          envFrom:
            - configMapRef: {name: shop-api-config}
          env:
            # ── JVM options from a ConfigMap so ops can tune without a rebuild ──
            - name: JAVA_OPTS
              valueFrom: {configMapKeyRef: {name: shop-api-jvm, key: JAVA_OPTS}}
            # ── credentials as FILES, not env ──
            - {name: SPRING_DATASOURCE_USERNAME_FILE, value: /run/secrets/db/username}
            - {name: SPRING_DATASOURCE_PASSWORD_FILE, value: /run/secrets/db/password}
            # ── Downward API ──
            - name: POD_NAME
              valueFrom: {fieldRef: {fieldPath: metadata.name}}
            - name: POD_NAMESPACE
              valueFrom: {fieldRef: {fieldPath: metadata.namespace}}
            - name: POD_IP
              valueFrom: {fieldRef: {fieldPath: status.podIP}}
            - name: NODE_NAME
              valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
            - name: APP_VERSION
              value: "1.0.0"

          # ── ⭐ THE MEMORY MATH. See §9.7. limit 1Gi → MaxRAMPercentage 70 → heap ~716MB ──
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
              ephemeral-storage: 256Mi
            limits:
              cpu: "2"
              memory: 1Gi                # == request → Guaranteed QoS for memory
              ephemeral-storage: 1Gi

          # ── ⭐ THREE probes, each doing exactly one job ──
          startupProbe:
            # "has the JVM finished booting?" — up to 4 minutes
            httpGet: {path: /actuator/health/liveness, port: http}
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 48          # 5s × 48 = 240s
          readinessProbe:
            # "can this replica take traffic RIGHT NOW?" — includes the DB
            httpGet: {path: /actuator/health/readiness, port: http}
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
            successThreshold: 1
          livenessProbe:
            # "is the JVM deadlocked?" — ONLY checks the app, NEVER a dependency
            httpGet: {path: /actuator/health/liveness, port: http}
            periodSeconds: 20
            timeoutSeconds: 5             # generous: a GC pause can exceed 3s
            failureThreshold: 3

          lifecycle:
            preStop:
              exec:
                # 1. sleep → let endpoints propagate & the LB stop routing
                # 2. then Spring's graceful shutdown drains in-flight requests on SIGTERM
                command: ["/bin/sh", "-c", "sleep 10"]

          volumeMounts:
            - {name: tmp,        mountPath: /tmp}              # heap dumps, JVM temp
            - {name: db-secret,  mountPath: /run/secrets/db, readOnly: true}
            - {name: app-config, mountPath: /app/config, readOnly: true}

      volumes:
        - {name: tmp, emptyDir: {sizeLimit: 1Gi}}
        - name: db-secret
          secret:
            secretName: db-creds
            defaultMode: 0400
        - name: app-config
          configMap:
            name: shop-api-config
            items:
              - {key: SPRING_PROFILES_ACTIVE, path: active-profile.txt}
            optional: true
```

> 🔑 **`SPRING_DATASOURCE_PASSWORD_FILE`** — Spring Boot 3 natively supports `*_FILE` for many properties, but not universally. If your version doesn't, read the file in a tiny `@Configuration`:
> ```java
> @Bean DataSourceProperties dataSourceProperties(
>     @Value("${SPRING_DATASOURCE_PASSWORD_FILE:}") String pwFile) throws IOException {
>   var p = new DataSourceProperties();
>   p.setUrl(env.getProperty("SPRING_DATASOURCE_URL"));
>   p.setPassword(Files.readString(Path.of(pwFile)).trim());
>   return p;
> }
> ```
> Or simply use `valueFrom.secretKeyRef` — env-var secrets are fine if you accept the trade-offs from [Project 3 §3.6](06-PROJECT-3-config-secrets.md).

`k8s/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata: {name: shop-api, namespace: shop, labels: {app: shop-api}}
spec:
  type: ClusterIP
  selector: {app: shop-api}
  ports:
    - {name: http, port: 8080, targetPort: http}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: shop-api, namespace: shop}
spec:
  maxUnavailable: 1                 # with 3+ replicas and HPA, maxUnavailable beats minAvailable
  selector: {matchLabels: {app: shop-api}}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: shop-api, namespace: shop}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: shop-api}
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
    # ⭐ better for a JVM: scale on request rate, not CPU
    # - type: Pods
    #   pods:
    #     metric: {name: http_server_requests_per_second}
    #     target: {type: AverageValue, averageValue: "50"}
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - {type: Percent, value: 100, periodSeconds: 60}
        - {type: Pods,    value: 2,   periodSeconds: 60}
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 600     # ⭐ JVMs are expensive to start; don't churn
      policies:
        - {type: Percent, value: 10, periodSeconds: 60}
      selectPolicy: Min
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: shop-api, namespace: shop}
spec:
  podSelector: {matchLabels: {app: shop-api}}
  policyTypes: [Ingress, Egress]
  ingress:
    # from the Ingress controller
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: ingress-nginx}}
          podSelector: {matchLabels: {app.kubernetes.io/name: ingress-nginx}}
      ports: [{protocol: TCP, port: 8080}]
    # from Prometheus
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: monitoring}}
      ports: [{protocol: TCP, port: 8080}]
    # from the frontend Pods (if they proxy server-side)
    - from:
        - podSelector: {matchLabels: {app: shop-ui}}
      ports: [{protocol: TCP, port: 8080}]
  egress:
    # to the database
    - to: [{podSelector: {matchLabels: {app: db}}}]
      ports: [{protocol: TCP, port: 5432}]
    # DNS
    - to: [{namespaceSelector: {}}]
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
    # OTLP collector (tracing)
    - to: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: tracing}}}]
      ports: [{protocol: TCP, port: 4317}]
```

`k8s/servicemonitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: shop-api
  namespace: monitoring
  labels: {release: kps}
spec:
  namespaceSelector: {matchNames: [shop]}
  selector: {matchLabels: {app: shop-api}}
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 15s
      scrapeTimeout: 10s
```

Deploy:

```bash
kubectl apply -f k8s/namespace.yaml -f k8s/config.yaml
kubectl apply -f k8s/deployment.yaml -f k8s/service.yaml -f k8s/servicemonitor.yaml
kubectl rollout status deploy/shop-api -n shop --timeout=300s
kubectl get deploy,pods,svc,hpa,pdb,netpol -n shop
```

---

## 9.7 ⭐ The JVM memory math (the part that stops OOMKills)

**A JVM's total footprint is much more than its heap.** This is why "I gave it 1 GB and it still got OOMKilled" happens:

| Region | Typical size with a 700 MB heap | Controllable by |
|---|---|---|
| **Heap** | 700 MB | `-XX:MaxRAMPercentage` / `-Xmx` |
| Metaspace (class metadata) | 80–150 MB | `-XX:MaxMetaspaceSize` |
| Code cache (JIT compiled code) | 50–240 MB | `-XX:ReservedCodeCacheSize` |
| **Thread stacks** | 1 MB × N threads | `-Xss`, and *reducing thread count* |
| GC structures | 5–15% of heap | GC choice |
| Direct/NIO buffers | varies | `-XX:MaxDirectMemorySize` |
| JNI / native libs (netty, zip, crypto) | 20–100 MB | — |
| glibc arenas | up to 64 MB × cores | `MALLOC_ARENA_MAX=2` |

**With 200 threads (Tomcat's default pool + Hikari + Micrometer + GC), thread stacks alone are 200 MB.**

### The rule

```
container memory limit  ≥  heap × 1.4  +  100 MB slack

Equivalently:  MaxRAMPercentage ≈ 70% of the limit
               (60% for a very thread-heavy app, 75% for a lean one)
```

| Container limit | `MaxRAMPercentage` | Approx heap | Leaves for non-heap |
|---|---|---|---|
| 512 Mi | 60% | 307 MB | 205 MB — tight, risky |
| 1 Gi | 70% | 716 MB | 308 MB — good |
| 2 Gi | 70% | 1.4 Gi | 620 MB — good |
| 4 Gi | 75% | 3 Gi | 1 Gi — comfortable |

**Never set `-Xmx` equal to the container limit.** `-Xmx1g` in a 1 Gi container is a guaranteed OOMKill within minutes.

### Verify the JVM sees the container

```bash
kubectl exec -n shop deploy/shop-api -- java -XshowSettings:properties -version 2>&1 | grep -iE 'cgroup|container'
kubectl exec -n shop deploy/shop-api -- sh -c 'cat /sys/fs/cgroup/memory.max'
# 1073741824                                  ← the container limit, in bytes
kubectl exec -n shop deploy/shop-api -- jcmd 1 VM.flags | tr ' ' '\n' | grep -iE 'MaxHeapSize|MaxRAMPercentage|UseContainerSupport'
# -XX:+UseContainerSupport                    ← on by default since JDK 10
# -XX:MaxHeapSize=751619276                   ← ~716 MB ✅
```

### Watch it live

```bash
curl -s localhost:8080/actuator/prometheus | grep -E '^jvm_memory_(used|max)_bytes\{area=' | head
curl -s localhost:8080/actuator/metrics/jvm.memory.used | jq .
curl -s 'localhost:8080/actuator/metrics/jvm.memory.used?tag=area:nonheap' | jq .
```

```promql
# heap usage vs container limit — alert above 0.9
jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}

# non-heap (the part people forget)
sum by (pod) (jvm_memory_used_bytes{area="nonheap"})

# GC pause ratio — if this exceeds 0.1, your app spends 10% of its time in GC
rate(jvm_gc_pause_seconds_sum[5m])

# threads (each one costs ~1 MB of stack)
jvm_threads_live_threads
```

### Deliberately OOMKill it, then read the evidence

```bash
kubectl port-forward -n shop svc/shop-api 8080:8080 &
sleep 2
curl -s localhost:8080/api/chaos/oom &
sleep 20
kubectl get pods -n shop -l app=shop-api
# shop-api-xxx   0/1   OOMKilled   0   3m
kubectl describe pod -n shop -l app=shop-api | grep -A6 "Last State"
#     Last State:     Terminated
#       Reason:       OOMKilled
#       Exit Code:    137
kubectl logs -n shop -l app=shop-api --previous --tail=30
kill %1 %2 2>/dev/null
```

Two things to notice:
1. `-XX:+ExitOnOutOfMemoryError` makes the JVM exit **immediately** on a Java-level OOM instead of limping along in a broken state. Kubernetes then restarts it cleanly. Without that flag, a JVM can survive a heap OOM in a zombie state — worse than dying.
2. `-XX:+HeapDumpOnOutOfMemoryError` writes `/tmp/*.hprof` — but `/tmp` is an `emptyDir`, so it dies with the Pod. For real forensics, mount a PVC at `/tmp/dumps` or ship dumps to object storage.

### Other JVM-on-Kubernetes must-knows

```bash
# ── CPU: the JVM reads the CPU limit and sizes its thread pools ──
kubectl exec -n shop deploy/shop-api -- sh -c 'cat /sys/fs/cgroup/cpu.max'
# 200000 100000    → 2 CPUs
kubectl exec -n shop deploy/shop-api -- java -XX:+PrintFlagsFinal -version 2>/dev/null | grep -i availableProcessors
# AvailableProcessors = 2  → ForkJoinPool.commonPool, GC threads, Tomcat's NIO all sized from this

# ⚠️ A low CPU request (e.g. 100m) makes the JVM see 0.1 CPUs → it sets
#    AvailableProcessors=1 → single GC thread, tiny thread pools, terrible throughput.
#    FIX: raise requests.cpu to at least 500m, or override:
#    -XX:ActiveProcessorCount=4
```

```bash
# ── CPU throttling check (Java is very sensitive to this) ──
```
```promql
sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{pod=~"shop-api.*"}[5m]))
/
sum by (pod) (rate(container_cpu_cfs_periods_total{pod=~"shop-api.*"}[5m]))
```

A throttled JVM has **stalled GC threads** — that shows up as p99 latency spikes with no errors. For Java, strongly consider **removing `limits.cpu`** entirely and relying on `requests.cpu` + HPA.

```bash
# ── glibc arena bloat (only on glibc-based images, not alpine/musl) ──
# MALLOC_ARENA_MAX=2 in the Deployment env; can save 100-300 MB on multi-core nodes

# ── CDS: faster JVM startup (AppCDS) ──
# In the Dockerfile, after copying layers:
RUN java -XX:ArchiveClassesAtExit=/app/app.jsa -Dspring.context.exit=onRefresh \
         -Djarmode=tools -jar app.jar || true
# then at runtime: -XX:SharedArchiveFile=/app/app.jsa
# Cuts Spring Boot startup by ~20-40%

# ── Spring Boot 3.3+ checkpoint/restore (CRaC) — startup in milliseconds ──
# Requires a CRaC-enabled JDK (Azul Zulu / BellSoft Liberica CRaC) and CRaC-compatible deps.
```

---

## 9.8 Probes: the Spring Boot way, and why liveness must never touch the DB

Spring Boot exposes exactly what Kubernetes wants, once you enable it:

```yaml
management.endpoint.health.probes.enabled: true
```

```bash
curl -s localhost:8080/actuator/health/liveness  | jq .
# {"status":"UP","groups":["livenessState"]}          ← ONLY the app
curl -s localhost:8080/actuator/health/readiness | jq .
# {"status":"UP","groups":["readinessState","db"]}    ← app + dependencies
```

**The configuration that matters:**

```yaml
management:
  endpoint:
    health:
      group:
        liveness:
          include: livenessState          # ⭐ ONLY this. No db, no redis, no diskSpace.
        readiness:
          include: readinessState,db      # ⭐ dependencies belong HERE
      probes:
        enabled: true
```

### Why this distinction prevents outages

**Wrong (very common):**

```yaml
livenessProbe: {httpGet: {path: /actuator/health}}     # includes db!
```

What happens when the database blips for 40 seconds:

```
t=0    db slow → /actuator/health returns DOWN
t=20   liveness fails (failureThreshold 3 × periodSeconds 20)
t=20   Kubernetes RESTARTS every shop-api pod
t=25   30 pods boot simultaneously, each opening 10 Hikari connections
t=26   the recovering database is crushed by 300 new connections
t=30   db still down → liveness fails again → restart again
       ⛔ SELF-INFLICTED OUTAGE. The database would have recovered on its own.
```

**Right:**

```yaml
livenessProbe:  {httpGet: {path: /actuator/health/liveness}}    # only "is the JVM alive"
readinessProbe: {httpGet: {path: /actuator/health/readiness}}   # includes db
```

```
t=0    db slow → readiness fails
t=10   pods marked NotReady → removed from Service endpoints → no traffic
       (the pods are STILL RUNNING and will serve again the moment db recovers)
t=40   db recovers → readiness passes → back in rotation. Zero restarts.
```

> 🔑 **Liveness answers "should this be killed?". Readiness answers "should this get traffic?".** A dependency outage is never a reason to kill your app.

### Probe timing for a JVM

| Probe | periodSeconds | failureThreshold | Total |
|---|---|---|---|
| `startupProbe` | 5 | 48 | 240 s to boot (Spring Boot can be slow with a big classpath) |
| `livenessProbe` | 20 | 3 | 60 s to detect a true hang |
| `readinessProbe` | 10 | 3 | 30 s to leave rotation |

`timeoutSeconds: 5` on liveness, because a long GC pause can exceed 3 s and you don't want to restart a Pod for one 4-second STW pause.

---

## 9.9 Graceful shutdown, end to end

Four things must line up. Get one wrong and you drop requests on every deploy.

```yaml
# 1. Spring: drain in-flight requests on SIGTERM
server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 25s

# 2. Pod: give the drain time, and buy propagation time first
spec:
  terminationGracePeriodSeconds: 60
  containers:
    - lifecycle:
        preStop: {exec: {command: ["/bin/sh","-c","sleep 10"]}}

# 3. PID 1 must forward SIGTERM
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["sh","-c","exec java $JAVA_OPTS org.springframework.boot.loader.launch.JarLauncher"]
#                                        ⭐ `exec` replaces the shell so java receives signals

# 4. Readiness must go DOWN early so traffic stops
```

**The exact timeline on `kubectl delete pod`:**

```
t=0.0s   delete → Pod marked Terminating
         ├─► EndpointSlice updated → kube-proxy & ingress remove this Pod   (async, ~0.1-3s)
         └─► preStop runs: sleep 10                                          (async)
t=10.0s  preStop done → kubelet sends SIGTERM to tini → tini forwards to java
t=10.1s  Spring: stops accepting new requests, starts the 25s drain window
t=10.5s  Actuator readiness flips to DOWN (management.endpoint.health → OUT_OF_SERVICE)
t=~12s   in-flight requests complete; Tomcat threads shut down; Hikari pool closes
t=12.5s  JVM exits 0
t=12.6s  Pod deleted
         (grace period was 60s — we used 12.6s. Plenty of margin.)
```

Verify it:

```bash
kubectl logs -n shop -f deploy/shop-api &
LOGS=$!
kubectl delete pod -n shop -l app=shop-api --field-selector metadata.name=$(kubectl get pod -n shop -l app=shop-api -o jsonpath='{.items[0].metadata.name}')
wait $LOGS
```

```
… Commencing graceful shutdown. Waiting for active requests to complete
… Graceful shutdown complete
```

If instead you see nothing and the Pod takes exactly 60 s to disappear → SIGKILL after the grace period → **SIGTERM never reached the JVM**. Causes:

| Symptom | Cause | Fix |
|---|---|---|
| Pod always takes exactly `terminationGracePeriodSeconds` | Signals not forwarded | `ENTRYPOINT` exec form, or `exec` in the CMD shell, or tini |
| Logs show no "graceful shutdown" | `server.shutdown: graceful` missing | Add it |
| "Graceful shutdown aborted with N request(s) still active" | `timeout-per-shutdown-phase` too short | Raise it; find the slow endpoint |
| 502s in the load test anyway | preStop too short vs. LB propagation | Raise `sleep` to 15 |

Prove it with load:

```bash
hey -z 90s -q 30 -c 5 -host shop.example.com "http://$LB_IP/api/products" > during.txt &
HEY=$!
sleep 3
kubectl rollout restart deploy/shop-api -n shop
kubectl rollout status deploy/shop-api -n shop
wait $HEY
grep -A3 'Status code distribution' during.txt
# [200] 2700 responses          ← zero 502s ✅
```

---

## 9.10 Database migrations: Flyway, not `ddl-auto`

```xml
<dependency>
  <groupId>org.flywaydb</groupId>
  <artifactId>flyway-core</artifactId>
</dependency>
<dependency>
  <groupId>org.flywaydb</groupId>
  <artifactId>flyway-database-postgresql</artifactId>
</dependency>
```

`src/main/resources/db/migration/V1__create_products.sql`:

```sql
CREATE TABLE IF NOT EXISTS products (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(120) NOT NULL,
    price       DOUBLE PRECISION NOT NULL CHECK (price >= 0),
    description VARCHAR(2000),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_products_name ON products (lower(name));
```

`src/main/resources/db/migration/V2__add_sku.sql`:

```sql
ALTER TABLE products ADD COLUMN sku VARCHAR(40);
CREATE UNIQUE INDEX IF NOT EXISTS uq_products_sku ON products (sku) WHERE sku IS NOT NULL;
```

```yaml
spring:
  flyway:
    enabled: true
    baseline-on-migrate: true
    locations: classpath:db/migration
    lock-retry-count: 3          # if another pod holds the lock, retry
  jpa:
    hibernate:
      ddl-auto: validate         # ⭐ validate, never update/create
```

### Three ways to run migrations in Kubernetes

**A. In-app on startup (simplest, and fine for most teams)**

Every replica runs Flyway on boot; Flyway takes an advisory lock so only one wins. Add a startup probe with a long budget.

Downside: if a migration takes 10 minutes, all 30 Pods are blocked booting and your rollout stalls.

**B. A pre-upgrade Job (recommended for anything non-trivial)**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: shop-api-migrate-1.0.0
  namespace: shop
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 0                 # ⭐ NEVER auto-retry a half-applied migration
  activeDeadlineSeconds: 900
  ttlSecondsAfterFinished: 604800
  template:
    spec:
      restartPolicy: Never
      securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: migrate
          image: ghcr.io/3558bhk/shop-api:1.0.0
          command: ["sh","-c","java $JAVA_OPTS -Dspring.main.web-application-type=none org.springframework.boot.loader.launch.JarLauncher"]
          env:
            - {name: SPRING_PROFILES_ACTIVE, value: "prod,migrate"}
            - {name: SPRING_FLYWAY_ENABLED,  value: "true"}
            - {name: JAVA_OPTS, value: "-XX:MaxRAMPercentage=60"}
          envFrom: [{configMapRef: {name: shop-api-config}}]
          resources: {requests: {cpu: 250m, memory: 512Mi}, limits: {memory: 1Gi}}
```

**C. Expand → migrate → contract (zero-downtime schema changes)**

The pattern that lets you migrate while the old version is still serving:

```sql
-- v1.4.2 deploy: EXPAND (additive only, old code ignores it)
ALTER TABLE products ADD COLUMN sku VARCHAR(40);
CREATE INDEX CONCURRENTLY idx_products_sku ON products (sku);   -- CONCURRENTLY = no table lock

-- v1.5.0 deploy: MIGRATE (backfill; both old and new code work)
UPDATE products SET sku = 'LEGACY-' || id WHERE sku IS NULL;

-- v1.6.0 deploy: CONTRACT (remove the old path)
ALTER TABLE products ALTER COLUMN sku SET NOT NULL;
```

Rules: never rename a column in one step (add → dual-write → backfill → switch reads → drop). Never add a `NOT NULL` column without a default in one step. Always use `CREATE INDEX CONCURRENTLY` on Postgres.

---

## 9.11 Extra Tasks

### Task 9.1 — Prove the readiness/liveness distinction with a real outage

Simulate a 60-second database outage and show that a *correctly configured* app survives it while a misconfigured one self-destructs.

<details>
<summary>Show answer</summary>

**Part A — the WRONG configuration.**

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api-wrong, namespace: shop, labels: {app: api-wrong}}
spec:
  replicas: 3
  selector: {matchLabels: {app: api-wrong}}
  template:
    metadata: {labels: {app: api-wrong}}
    spec:
      containers:
        - name: api
          image: ghcr.io/3558bhk/shop-api:1.0.0
          ports: [{containerPort: 8080}]
          envFrom: [{configMapRef: {name: shop-api-config}}]
          # ⛔ liveness = the FULL health endpoint, which includes the db
          livenessProbe:
            httpGet: {path: /actuator/health, port: 8080}
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet: {path: /actuator/health, port: 8080}
            periodSeconds: 10
          resources: {requests: {cpu: 250m, memory: 768Mi}, limits: {memory: 1Gi}}
EOF
kubectl rollout status deploy/api-wrong -n shop
```

Now kill the database:

```bash
# watch restarts in one terminal
kubectl get pods -n shop -l app=api-wrong -w > wrong.log &
W=$!

# take the db down for 60 seconds
kubectl scale deploy/db -n shop --replicas=0
sleep 60
kubectl scale deploy/db -n shop --replicas=1
kubectl rollout status deploy/db -n shop

sleep 60; kill $W
grep -cE '[1-9][0-9]*\s+[1-9]' wrong.log || true
kubectl get pods -n shop -l app=api-wrong
```

```
NAME                         READY   STATUS    RESTARTS      AGE
api-wrong-7d9f8-x2k4j        1/1     Running   3 (45s ago)   8m     ← ⛔ restarted 3×
api-wrong-7d9f8-mn3p8        1/1     Running   3 (42s ago)   8m
api-wrong-7d9f8-qw7rt        1/1     Running   3 (48s ago)   8m
```

```bash
kubectl logs -n shop deploy/api-wrong --previous --tail=20
# …APPLICATION FAILED TO START… / Connection refused / HikariPool-1 - Exception during pool initialization
kubectl describe pod -n shop -l app=api-wrong | grep -A4 "Last State"
#   Reason: Error   Exit Code: 1     ← liveness killed it
```

Every Pod restarted, several times, during a database blip that would have passed. Each restart costs ~20 s of JVM boot during which that Pod serves nothing — and 3 Pods × 3 restarts = a much worse outage than the original 60-second DB blip.

**Part B — the RIGHT configuration.**

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api-right, namespace: shop, labels: {app: api-right}}
spec:
  replicas: 3
  selector: {matchLabels: {app: api-right}}
  template:
    metadata: {labels: {app: api-right}}
    spec:
      containers:
        - name: api
          image: ghcr.io/3558bhk/shop-api:1.0.0
          ports: [{containerPort: 8080}]
          envFrom: [{configMapRef: {name: shop-api-config}}]
          # ✅ liveness = JVM only
          livenessProbe:
            httpGet: {path: /actuator/health/liveness, port: 8080}
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 3
          # ✅ readiness = app + dependencies
          readinessProbe:
            httpGet: {path: /actuator/health/readiness, port: 8080}
            periodSeconds: 10
            failureThreshold: 3
          startupProbe:
            httpGet: {path: /actuator/health/liveness, port: 8080}
            periodSeconds: 5
            failureThreshold: 48
          resources: {requests: {cpu: 250m, memory: 768Mi}, limits: {memory: 1Gi}}
EOF
kubectl rollout status deploy/api-right -n shop

kubectl get pods -n shop -l app=api-right -w > right.log &
W=$!
kubectl scale deploy/db -n shop --replicas=0
sleep 60
kubectl scale deploy/db -n shop --replicas=1
kubectl rollout status deploy/db -n shop
sleep 60; kill $W

kubectl get pods -n shop -l app=api-right
```

```
NAME                         READY   STATUS    RESTARTS   AGE
api-right-6c5d4-abc12        1/1     Running   0          10m     ← ZERO restarts ✅
```

And during the outage, `READY` went to `0/1` — traffic was correctly withheld, then restored:

```bash
grep -E '0/1|1/1' right.log | head -20
# api-right-6c5d4-abc12   1/1   Running   0   8m
# api-right-6c5d4-abc12   0/1   Running   0   9m     ← NotReady during the DB outage
# api-right-6c5d4-abc12   1/1   Running   0   10m    ← recovered on its own
```

**Part C — prove endpoints were actually withdrawn.**

```bash
kubectl scale deploy/db -n shop --replicas=0
sleep 20
kubectl get endpointslices -n shop -l kubernetes.io/service-name=api-right \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
# 10.244.1.30 ready=false
# 10.244.2.41 ready=false      ← all withdrawn; the Service returns 503 (correct!)
kubectl scale deploy/db -n shop --replicas=1 && kubectl rollout status deploy/db -n shop
sleep 20
kubectl get endpointslices -n shop -l kubernetes.io/service-name=api-right \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
# all ready=true                ← back in rotation, no restarts
```

**The lesson, in one line for the interview:** *"Liveness must only test the process itself. If liveness depends on a downstream service, a downstream blip becomes a fleet-wide restart storm — a self-inflicted outage far worse than the original problem. Dependencies belong in readiness."*

</details>

---

### Task 9.2 — Fix an OOMKilled Spring Boot app

`kubectl describe pod` says `Reason: OOMKilled, Exit Code: 137`. `kubectl top` says memory is only 700 MB and the limit is 1 Gi. Explain and fix.

<details>
<summary>Show answer</summary>

**Why `kubectl top` lied to you:** metrics-server samples every **15–60 s** and reports `container_memory_working_set_bytes` at that instant. An OOMKill is instantaneous — a 300 MB spike between samples is invisible. Also, if the app was already killed, the sample you're looking at is from the *new* container.

**Step 1 — confirm it really is OOM, and which kind.**

```bash
kubectl describe pod -n shop -l app=shop-api | grep -B2 -A8 "Last State"
```

```
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Mon, 09 Sep 2026 14:02:11 +0530
      Finished:     Mon, 09 Sep 2026 14:19:47 +0530
```

| Reason | Exit | Meaning |
|---|---|---|
| `OOMKilled` | 137 | **cgroup** memory limit exceeded — the kernel killed it. Container-level. |
| `Error` | 1 | JVM threw `OutOfMemoryError` and *exited* (because of `+ExitOnOutOfMemoryError`). Heap-level. |
| `Error` | 3 | JVM crashed / native OOM |
| `OOMKilled` on the **node** | — | `Evicted` status instead; node-level pressure |

**Step 2 — get the real peak from Prometheus, not `kubectl top`.**

```promql
# max over the last hour, per pod
max_over_time(container_memory_working_set_bytes{pod=~"shop-api.*"}[1h]) / 1024 / 1024

# vs the limit
kube_pod_container_resource_limits{resource="memory",pod=~"shop-api.*"} / 1024 / 1024

# the JVM's own view — heap vs non-heap
jvm_memory_used_bytes{area="heap",pod=~"shop-api.*"} / 1024 / 1024
jvm_memory_used_bytes{area="nonheap",pod=~"shop-api.*"} / 1024 / 1024

# OOMKill count
increase(kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}[6h])
```

Suppose you find: heap peaked at 690 MB (max 716 MB), non-heap at 180 MB, and the container hit 1024 MB. **690 + 180 + thread stacks + native = over 1 GiB.** Classic.

**Step 3 — account for every byte.**

```bash
kubectl exec -n shop deploy/shop-api -- jcmd 1 GC.heap_info
# garbage-first heap   total 751616K, used 690432K
#  region size 1024K, 120 young, 18 survivors
#  Metaspace  used 142336K, committed 145408K

kubectl exec -n shop deploy/shop-api -- jcmd 1 VM.native_memory summary    # needs -XX:NativeMemoryTracking=summary
kubectl exec -n shop deploy/shop-api -- jcmd 1 Thread.print | grep -c '^"'  # thread count
# 214      ← 214 threads × 1 MB stack = 214 MB right there

kubectl exec -n shop deploy/shop-api -- jcmd 1 VM.flags | tr ' ' '\n' | grep -iE 'MaxHeap|MaxMetaspace|ReservedCodeCache|ThreadStackSize'
```

| Component | Command to measure | Typical |
|---|---|---|
| Heap | `jcmd 1 GC.heap_info` | 70% of the limit |
| Metaspace | `jcmd 1 VM.metaspace` | 100–200 MB |
| Code cache | `jcmd 1 Compiler.codecache` | 50–240 MB |
| Thread stacks | thread count × `-Xss` (1 MB default) | **often 100–300 MB** |
| Direct buffers | `jcmd 1 VM.native_memory` or `BufferPoolMXBean` | varies |
| GC overhead | ~10% of heap | 70 MB |

**Step 4 — apply the fixes, in order of leverage.**

```bash
# FIX 1: lower MaxRAMPercentage to leave real room for non-heap
kubectl patch deploy shop-api -n shop --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/env/0/value",
   "value":"-XX:MaxRAMPercentage=60.0 -XX:MaxMetaspaceSize=256m -XX:ReservedCodeCacheSize=128m -Xss512k -XX:+ExitOnOutOfMemoryError -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp"}
]'

# FIX 2: reduce the thread count (biggest non-heap win)
#   Tomcat: server.tomcat.threads.max=100 (default 200)
#   Hikari: maximumPoolSize=10 (NOT 50 — see below)
kubectl patch cm shop-api-config -n shop --type=merge -p '{"data":{
  "SERVER_TOMCAT_THREADS_MAX":"100",
  "SERVER_TOMCAT_ACCEPT_COUNT":"100",
  "DB_POOL_SIZE":"10"}}'

# FIX 3: cap the pools that grow silently
#   -XX:MaxMetaspaceSize=256m      → metaspace can't eat the container
#   -XX:ReservedCodeCacheSize=128m → JIT can't either
#   -XX:MaxDirectMemorySize=128m   → Netty/NIO buffers
#   -Xss512k                       → halve every thread stack
#   MALLOC_ARENA_MAX=2             → glibc arena bloat (glibc images only)

# FIX 4: raise the limit (the honest answer when the app genuinely needs it)
kubectl patch deploy shop-api -n shop --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"2Gi"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"2Gi"}
]'
kubectl rollout status deploy/shop-api -n shop
```

**The connection-pool trap** — a HikariCP pool of 50 in 30 Pods is **1500 connections** to your database:

```
pool_size = (core_count × 2) + effective_spindle_count
          ≈ 10 for almost every OLTP service
```

```sql
-- Postgres: check what you're actually using
SELECT count(*), state FROM pg_stat_activity GROUP BY state;
SHOW max_connections;                 -- default 100. With 30 pods × 10, you're at 300.
```

If you need more, add **PgBouncer** as a sidecar or a Deployment — not bigger pools.

**Step 5 — verify, and set up the alarm so it never surprises you again.**

```promql
# alert: JVM using >90% of the container limit
(container_memory_working_set_bytes{pod=~"shop-api.*"}
 / on(pod) kube_pod_container_resource_limits{resource="memory"}) > 0.9
```

```yaml
- alert: ContainerMemoryNearLimit
  expr: |
    container_memory_working_set_bytes{namespace="shop"}
    / on(namespace, pod, container)
    kube_pod_container_resource_limits{resource="memory"} > 0.9
  for: 5m
  labels: {severity: warning}
  annotations:
    summary: "{{ $labels.pod }}/{{ $labels.container }} at {{ $value | humanizePercentage }} of its memory limit"
    description: "OOMKill is imminent. Run: kubectl exec {{ $labels.pod }} -- jcmd 1 GC.heap_info"
```

```bash
# and confirm the fix
kubectl get pods -n shop -l app=shop-api -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount,QOS:.status.qosClass'
sleep 1800
kubectl get pods -n shop -l app=shop-api    # RESTARTS still 0 ✅
```

**Prevention checklist for every JVM on Kubernetes:**
- [ ] `MaxRAMPercentage` ≈ 60–70%, never `-Xmx == limit`
- [ ] `MaxMetaspaceSize`, `ReservedCodeCacheSize`, `MaxDirectMemorySize` all capped
- [ ] `-Xss512k` unless you have genuinely deep recursion
- [ ] `+ExitOnOutOfMemoryError` so a broken JVM dies fast instead of limping
- [ ] `+HeapDumpOnOutOfMemoryError` with `HeapDumpPath` on a **PVC**, not an emptyDir
- [ ] Tomcat `threads.max` and Hikari `maximumPoolSize` explicitly set
- [ ] `requests.memory == limits.memory` → Guaranteed QoS → evicted last
- [ ] A `ContainerMemoryNearLimit` alert at 90%

</details>

---

### Task 9.3 — Scale the API on request rate instead of CPU

CPU is a poor scaling signal for a JVM (GC and JIT make it noisy). Build an HPA on a custom metric.

<details>
<summary>Show answer</summary>

**Step 1 — make sure the metric exists.**

```bash
kubectl port-forward -n shop svc/shop-api 8080:8080 &
sleep 2
curl -s localhost:8080/actuator/prometheus | grep -E '^http_server_requests_seconds_count' | head -3
# http_server_requests_seconds_count{exception="None",method="GET",outcome="SUCCESS",status="200",uri="/api/products"} 142.0
kill %1
```

Spring Boot + Micrometer exposes `http_server_requests_seconds_count` and `_sum` automatically once `management.metrics.distribution.percentiles-histogram.http.server.requests: true`.

**Step 2 — install Prometheus Adapter (the bridge between Prometheus and the K8s custom-metrics API).**

kube-prometheus-stack ships it:

```bash
helm upgrade kps prometheus-community/kube-prometheus-stack -n monitoring -f kps-values.yaml \
  --set prometheus-adapter.enabled=true \
  --set prometheus-adapter.prometheus.url=http://kps-kube-prometheus-stack-prometheus.monitoring.svc \
  --set prometheus-adapter.prometheus.port=9090
```

Configure the custom-metric rules:

```yaml
# prometheus-adapter custom rules
prometheus-adapter:
  prometheus:
    url: http://kps-kube-prometheus-stack-prometheus.monitoring
    port: 9090
  rules:
    default: false           # don't use the built-in generic rules
    custom:
      # ── requests per second, per pod ──
      - seriesQuery: 'http_server_requests_seconds_count{namespace!="",pod!=""}'
        seriesFilters: []
        resources:
          overrides:
            namespace: {resource: "namespace"}
            pod:       {resource: "pod"}
        name:
          as: "http_server_requests_per_second"
        metricsQuery: 'sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)'

      # ── p99 latency, per pod ──
      - seriesQuery: 'http_server_requests_seconds_bucket{namespace!="",pod!=""}'
        resources:
          overrides:
            namespace: {resource: "namespace"}
            pod:       {resource: "pod"}
        name:
          as: "http_server_requests_p99_seconds"
        metricsQuery: |
          histogram_quantile(0.99, sum(rate(<<.Series>>{<<.LabelMatchers>>}[5m])) by (le, <<.GroupBy>>))

      # ── HikariCP pending connections (a saturation signal that beats CPU) ──
      - seriesQuery: 'hikaricp_connections_pending{namespace!="",pod!=""}'
        resources:
          overrides:
            namespace: {resource: "namespace"}
            pod:       {resource: "pod"}
        name:
          as: "hikaricp_connections_pending"
        metricsQuery: 'sum(<<.Series>>{<<.LabelMatchers>>}) by (<<.GroupBy>>)'
```

**Step 3 — verify the custom-metrics API works.**

```bash
kubectl get apiservices | grep custom.metrics
# v1beta1.custom.metrics.k8s.io   monitoring/kps-prometheus-adapter   True   2m   ✅

kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq -r '.resources[].name' | head -20
# http_server_requests_per_second
# hikaricp_connections_pending
# pods/http_server_requests_p99_seconds

kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/shop/pods/*/http_server_requests_per_second" | jq .
```

If this returns nothing, the HPA will show `<unknown>` and you'll debug for an hour. Fix it here first — usually the `seriesQuery` doesn't match, or the adapter can't reach Prometheus.

**Step 4 — the HPA.**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: shop-api, namespace: shop}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: shop-api}
  minReplicas: 3
  maxReplicas: 30
  metrics:
    # ── primary signal: request rate ──
    - type: Pods
      pods:
        metric: {name: http_server_requests_per_second}
        target: {type: AverageValue, averageValue: "50"}     # 50 rps per pod
    # ── safety net: don't let CPU run away ──
    - type: Resource
      resource:
        name: cpu
        target: {type: Utilization, averageUtilization: 80}
    # ── saturation signal: DB pool contention ──
    - type: Pods
      pods:
        metric: {name: hikaricp_connections_pending}
        target: {type: AverageValue, averageValue: "1"}
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - {type: Percent, value: 100, periodSeconds: 30}      # double in 30s
        - {type: Pods,    value: 4,   periodSeconds: 30}
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 600                          # ⭐ JVMs cost 20s+ to boot
      policies:
        - {type: Pods, value: 1, periodSeconds: 120}           # shed 1 pod per 2 min
      selectPolicy: Min
```

**Step 5 — pick the target value empirically. Don't guess.**

```bash
# what does one pod handle at acceptable latency?
kubectl scale deploy/shop-api -n shop --replicas=1
brew install hey
hey -z 120s -c 20 -q 50 -host shop.example.com "http://$LB_IP/api/products" | tee one-pod.txt
```

```
Requests/sec:              412.88
Latency distribution:
  50% in 0.0210 secs
  95% in 0.0890 secs
  99% in 0.4100 secs          ← p99 degrading
```

Drop the load until p99 is acceptable:

```bash
hey -z 120s -c 6 -q 10 -host shop.example.com "http://$LB_IP/api/products" | tee one-pod-60.txt
# Requests/sec: 58.2    p99: 0.0610 secs    ← healthy
```

So one Pod comfortably does ~50–60 rps at good latency → **`averageValue: "50"`**. That's how you choose the number, not by picking something round.

**Step 6 — test the scaling.**

```bash
kubectl get hpa -n shop -w &
W=$!
hey -z 180s -c 60 -q 200 -host shop.example.com "http://$LB_IP/api/products" > load.txt &
sleep 200
kill $W
kubectl get hpa -n shop
```

```
NAME       REFERENCE             TARGETS                       MINPODS MAXPODS REPLICAS AGE
shop-api   Deployment/shop-api   143/50 (avg), 12%/80% (cpu)   3       30      12       5m
```

```bash
kubectl get pods -n shop -l app=shop-api -o wide    # 12 pods, spread across nodes/zones
kubectl describe hpa shop-api -n shop | sed -n '/Events:/,$p'
# Normal  SuccessfulRescale  4m  horizontal-pod-autoscaler  New size: 6; reason: pods metric http_server_requests_per_second above target
```

**Why request rate beats CPU for a JVM:**

| Signal | Problem |
|---|---|
| CPU % | JIT compilation and GC make CPU spiky and *unrelated* to load. A freshly-started Pod shows 90% CPU while warming up → HPA scales out for no reason |
| Memory | Useless for scaling — a JVM's memory is set by `-Xmx`, not by load |
| **Request rate** | Directly proportional to load. Predictable. Tunable from a load test |
| **p99 latency** | The actual SLO. Scale before you breach it |
| **Queue depth / pending DB connections** | Saturation. The best leading indicator |

**Even better: KEDA**, which scales on Prometheus queries directly and can scale to zero:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: {name: shop-api, namespace: shop}
spec:
  scaleTargetRef: {name: shop-api}
  minReplicaCount: 3
  maxReplicaCount: 30
  cooldownPeriod: 300
  pollingInterval: 15
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown: {stabilizationWindowSeconds: 600, policies: [{type: Pods, value: 1, periodSeconds: 120}]}
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://kps-kube-prometheus-stack-prometheus.monitoring:9090
        metricName: rps_per_pod
        query: |
          sum(rate(http_server_requests_seconds_count{namespace="shop",pod=~"shop-api.*"}[2m]))
          /
          count(kube_pod_info{namespace="shop",pod=~"shop-api.*"})
        threshold: "50"
        activationThreshold: "1"
```

```bash
kubectl delete hpa shop-api -n shop      # ⚠️ KEDA creates its own HPA; two HPAs on one target = fighting
kubectl apply -f scaledobject.yaml
kubectl get scaledobject,hpa -n shop
```

</details>

---

### Task 9.4 — Debug a Spring Boot app that starts locally but fails in the cluster

It works with `docker run`. In Kubernetes it's `CrashLoopBackOff`. Find all the likely causes.

<details>
<summary>Show answer</summary>

The systematic ladder:

```bash
POD=$(kubectl get pod -n shop -l app=shop-api -o jsonpath='{.items[0].metadata.name}')

# 1. THE LOGS. Always first.
kubectl logs -n shop $POD --tail=100
kubectl logs -n shop $POD --previous --tail=100      # ⭐ the crashed instance
kubectl logs -n shop $POD -c wait-for-db             # the init container!

# 2. The events
kubectl describe pod -n shop $POD | sed -n '/Events:/,$p'

# 3. The exit code
kubectl get pod -n shop $POD -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'; echo | jq .
```

**The causes, ranked by how often they actually happen:**

### 1. The database hostname doesn't resolve or isn't reachable

```
Caused by: java.net.UnknownHostException: db
Caused by: org.postgresql.util.PSQLException: Connection to db:5432 refused
HikariPool-1 - Exception during pool initialization
```

```bash
kubectl exec -n shop $POD -- sh -c 'getent hosts db.shop.svc.cluster.local || nslookup db'
kubectl get svc -n shop
kubectl get endpointslices -n shop -l kubernetes.io/service-name=db
```

**The #1 sub-cause:** the JDBC URL says `jdbc:postgresql://db:5432/app` but the Service is `db.shop.svc.cluster.local` and the app is in a *different* namespace. Short names only resolve inside your own namespace.

**Fix:** always use the FQDN or at least `service.namespace`:
```yaml
SPRING_DATASOURCE_URL: "jdbc:postgresql://db.shop.svc.cluster.local:5432/app"
```

And add the `wait-for-db` init container so the failure is *obvious* rather than a Hikari stack trace.

### 2. OOMKilled before Spring finishes booting

```bash
kubectl describe pod -n shop $POD | grep -A4 "Last State"
#   Reason: OOMKilled   Exit Code: 137
```

A Spring Boot app needs **~400–600 MB just to start**. `limits.memory: 256Mi` = instant OOMKill, often with no logs at all.

```bash
kubectl get deploy shop-api -n shop -o jsonpath='{.spec.template.spec.containers[0].resources}'; echo | jq .
kubectl logs -n shop $POD --previous | tail -3     # empty? → killed mid-boot
```

**Fix:** 768 Mi minimum for a Spring Boot 3 app; 1 Gi comfortable. See §9.7.

### 3. Liveness probe kills it during startup

```
Warning  Unhealthy  30s (x5)  kubelet  Liveness probe failed: Get "http://10.244.1.30:8080/actuator/health": dial tcp ... connect: connection refused
Warning  Killing    25s       kubelet  Container api failed liveness probe, will be restarted
```

```bash
kubectl describe pod -n shop $POD | grep -E 'Liveness|Startup'
# Liveness: http-get http://:http/actuator/health delay=10s timeout=1s period=10s #failure=3
```

`initialDelaySeconds: 10` and Spring Boot takes 25 s → killed at t=40 s → restart → killed again → `CrashLoopBackOff`, forever, with a perfectly healthy app.

**Fix:** a `startupProbe` with a long budget. **Never** solve this with a huge `initialDelaySeconds` on liveness — that also delays detection of real hangs.

```yaml
startupProbe:
  httpGet: {path: /actuator/health/liveness, port: 8080}
  periodSeconds: 5
  failureThreshold: 48        # 240 seconds
```

### 4. ConfigMap/Secret key missing → `CreateContainerConfigError`

```bash
kubectl describe pod -n shop $POD | grep -i "Error:"
# Error: configmap "shop-api-config" not found
# Error: couldn't find key SPRING_DATASOURCE_URL in ConfigMap shop/shop-api-config
```

```bash
kubectl get cm,secret -n shop
kubectl get cm shop-api-config -n shop -o jsonpath='{.data}' | jq 'keys'
```

**Sub-cause:** the ConfigMap is in `default`, the Deployment is in `shop`. Both are namespaced.

### 5. Port mismatch

```yaml
# container listens on 8080 but:
ports: [{containerPort: 80}]
readinessProbe: {httpGet: {path: /actuator/health, port: 80}}
```

```bash
kubectl exec -n shop $POD -- sh -c 'netstat -tlnp 2>/dev/null || ss -tlnp'
# LISTEN 0 100 *:8080 *:*
kubectl get deploy shop-api -n shop -o jsonpath='{.spec.template.spec.containers[0].ports}'; echo
kubectl get svc shop-api -n shop -o jsonpath='{.spec.ports}'; echo
```

Note: `containerPort` is **documentation only** — Kubernetes doesn't enforce it. But probes and Services use it.

### 6. `readOnlyRootFilesystem: true` and the app writes somewhere

```
java.io.IOException: Read-only file system
  at java.base/java.io.UnixFileSystem.createFileExclusively
  ... /tmp/tomcat.8080.xxxx
```

```bash
kubectl exec -n shop $POD -- touch /tmp/test 2>&1
kubectl exec -n shop $POD -- touch /app/test 2>&1
# /app/test: Read-only file system       ← Tomcat's work dir!
```

Spring Boot/Tomcat writes to `java.io.tmpdir`. **Fix:**

```yaml
env: [{name: JAVA_OPTS, value: "... -Djava.io.tmpdir=/tmp"}]
volumeMounts: [{name: tmp, mountPath: /tmp}]
volumes: [{name: tmp, emptyDir: {sizeLimit: 512Mi}}]
```

### 7. `runAsNonRoot` and the image defaults to root

```
Error: failed to create containerd task: failed to create shim task:
  OCI runtime create failed: container_linux.go:380: starting container process caused:
  process_linux.go:449: container init caused: ... "container has runAsNonRoot and image will run as root"
```

```bash
docker inspect shop-api:case2 --format '{{.Config.User}}'
# 10001:10001   ✅
```

**Fix:** add `USER 10001` to the Dockerfile, or `runAsUser: 10001` in the Pod's `securityContext`. Then make sure everything the app touches is owned by that UID (`chown` in the Dockerfile, or `fsGroup`).

### 8. Image not in the cluster (kind/minikube)

```
Warning  Failed  ...  Failed to pull image "shop-api:1.0.0": rpc error: ... not found
```

```bash
docker images | grep shop-api          # exists locally
kind load docker-image shop-api:1.0.0 --name learn
# or
minikube image load shop-api:1.0.0
# and set imagePullPolicy: IfNotPresent or Never
```

### 9. Architecture mismatch

```
exec format error
```

Built on an M-series Mac (arm64), the cluster is amd64:

```bash
docker buildx build --platform linux/amd64 -t shop-api:1.0.0 --push .
docker manifest inspect ghcr.io/3558bhk/shop-api:1.0.0 | jq '.manifests[].platform'
```

### 10. Flyway/migration failure

```
Migration V2__add_sku.sql failed
SQL State  : 42P07
Error Code : 0
Message    : ERROR: relation "idx_products_sku" already exists
```

```bash
kubectl logs -n shop $POD --previous | grep -A20 "Flyway\|Migration"
kubectl exec -n shop deploy/db -- psql -U postgres -d app -c 'SELECT * FROM flyway_schema_history ORDER BY installed_rank;'
```

**Fix:** repair the history (`flyway repair`), or make migrations idempotent (`CREATE INDEX IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`). And set `backoffLimit: 0` on migration Jobs so they don't retry into a worse state.

**The universal first three commands, again:**

```bash
kubectl logs -n shop $POD --previous --tail=100
kubectl describe pod -n shop $POD | sed -n '/Events:/,$p'
kubectl get pod -n shop $POD -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'; echo
```

</details>

---

### Task 9.5 — Add distributed tracing to the Spring Boot API

Trace a request from the Ingress through the API to Postgres.

<details>
<summary>Show answer</summary>

**Step 1 — dependencies.**

```xml
<dependency>
  <groupId>io.micrometer</groupId>
  <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
  <groupId>io.opentelemetry</groupId>
  <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
```

**Step 2 — configuration.**

```yaml
management:
  tracing:
    sampling:
      probability: 1.0              # 100% in dev; 0.05-0.1 in prod
  otlp:
    tracing:
      endpoint: http://otel-collector.tracing.svc.cluster.local:4318/v1/traces
      timeout: 5s
  observations:
    annotations:
      enabled: true
  metrics:
    distribution:
      percentiles-histogram:
        http.server.requests: true

logging:
  pattern:
    # ⭐ trace_id and span_id in EVERY log line — this is what joins logs to traces
    console: "%d{HH:mm:ss.SSS} %-5level [${spring.application.name},%X{trace_id:-},%X{span_id:-}] %logger{36} - %msg%n"
```

Result in Loki:

```
14:22:01.123 INFO  [shop-api,4bf92f3577b34da6a31b2c05d3f2b1a4,b7ad6b7169203331] c.h.s.ProductController - list products q=null count=42
```

**Step 3 — the collector and backend** (from [Project 7 §7.10](10-PROJECT-7-observability.md)).

**Step 4 — instrument the JDBC layer.**

```xml
<dependency>
  <groupId>net.ttddyy.observation</groupId>
  <artifactId>datasource-micrometer-spring-boot</artifactId>
  <version>1.0.3</version>
</dependency>
```

That single dependency gives you a span for every SQL statement, with the query as an attribute. Enormous value for the effort.

**Step 5 — custom spans where it matters.**

```java
@Service
public class PricingService {
    private final ObservationRegistry registry;

    public BigDecimal price(Long productId, String region) {
        return Observation.createNotStarted("pricing.calculate", registry)
            .lowCardinalityKeyValue("region", region)          // safe as a metric label
            .highCardinalityKeyValue("product.id", productId.toString())  // trace attribute only
            .observe(() -> doPrice(productId, region));
    }
}
```

> ⚠️ **Cardinality discipline:** `lowCardinalityKeyValue` becomes a *metric* label — never put user IDs, order IDs, or request IDs there. `highCardinalityKeyValue` goes only into the trace. Getting this wrong turns your Prometheus into a smoking crater.

**Step 6 — propagate across services.**

Micrometer/OTel does W3C `traceparent` propagation automatically on `RestTemplate` (with `RestTemplateBuilder`), `WebClient`, and `RestClient`:

```java
@Bean
RestClient apiClient(RestClient.Builder builder) {
    return builder.baseUrl("http://inventory.shop.svc.cluster.local:8080").build();
}
// the builder is auto-instrumented → outgoing requests carry traceparent
```

For raw HTTP clients, inject manually:

```java
@Autowired Tracer tracer;
Span span = tracer.nextSpan().name("call-payment-gateway").start();
try (var ws = tracer.withSpan(span)) {
    request.header("traceparent", span.context().traceId());   // or use the propagator
    // ... call
} finally { span.end(); }
```

**Step 7 — verify.**

```bash
kubectl port-forward -n tracing svc/jaeger-query 16686:16686 &
sleep 2
curl -s "http://$LB_IP/api/products" -H "Host: shop.example.com" > /dev/null
curl -s "http://localhost:16686/api/services" | jq .
curl -s "http://localhost:16686/api/traces?service=shop-api&limit=5" | jq '.data[0].spans[].operationName'
kill %1
```

You should see one trace with spans: `HTTP GET /api/products` → `pricing.calculate` → `SELECT products…`.

**Step 8 — join it all in Grafana.**

Add trace_id to the Loki datasource's derived fields so you can click a log line and jump to its trace:

```yaml
datasources:
  - name: Loki
    type: loki
    jsonData:
      derivedFields:
        - datasourceUid: tempo
          matcherRegex: '\[shop-api,(\w+),\w+\]'
          name: TraceID
          url: '$${__value.raw}'
```

**What tracing actually buys you:**

| Question | Answer from |
|---|---|
| "Is it slow?" | Metrics (p99) |
| "Which *part* is slow?" | **Traces** |
| "What exactly did it log at that moment?" | Logs, filtered by trace_id |
| "How often does this happen?" | Metrics |

A trace showing `GET /api/checkout` = 2.1 s, with `SELECT inventory` = 1.9 s, ends an argument that metrics alone would keep alive for a week.

</details>

---

## 9.12 Checklist

- [ ] Write a layered multi-stage Dockerfile and prove layer caching works
- [ ] Explain the difference between the JDK, JRE, jlink and native-image runtimes
- [ ] Compute the right `MaxRAMPercentage` for a given container limit, and justify it
- [ ] List the six non-heap memory regions and how to cap each
- [ ] Configure Actuator's liveness and readiness groups correctly — and explain why
- [ ] Describe what goes wrong when liveness includes the database
- [ ] Wire `server.shutdown: graceful` + `preStop` + `terminationGracePeriodSeconds` + tini into a coherent shutdown timeline
- [ ] Use Flyway with `ddl-auto: validate`, run migrations from a pre-upgrade Job with `backoffLimit: 0`
- [ ] Explain expand → migrate → contract for zero-downtime schema changes
- [ ] Build an HPA on a custom request-rate metric via the Prometheus Adapter
- [ ] Diagnose a Spring Boot `CrashLoopBackOff` from logs + describe + exit code
- [ ] Add distributed tracing with trace IDs in every log line

**Next → [`13-PROJECT-10-react-java-fullstack.md`](13-PROJECT-10-react-java-fullstack.md)** — both stacks together, with NetworkPolicies and one-origin routing.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
