# Spring Boot - Annotations & Core - SDE3

## Spring Boot Advantages
- Auto-configuration, starter dependencies, embedded server (Tomcat/Jetty), production ready (actuator, metrics), no XML

## Main Annotations

### Core
```java
@SpringBootApplication // @Configuration + @EnableAutoConfiguration + @ComponentScan
public class App { public static void main(String[] args) { SpringApplication.run(App.class, args); } }

@Configuration // Bean definitions
@Component // Generic component
@Service // Business logic
@Repository // Data access, exception translation
@Controller // MVC controller returns view
@RestController // @Controller + @ResponseBody JSON
@Bean // Method returns bean
@ComponentScan
```

### Dependency Injection
```java
@Autowired // Field, setter, constructor (constructor preferred for testability, required from Spring 4.3 implicit)
@Qualifier("beanName") // When multiple beans same type
@Primary // Preferred when multiple
@Value("${app.name}") // Inject property
@Lazy // Lazy init
@Scope("singleton") // singleton (default), prototype, request, session
```

### MVC / REST
```java
@RequestMapping("/api") // Class or method
@GetMapping("/users/{id}")
@PostMapping("/users")
@PutMapping("/users/{id}")
@PatchMapping
@DeleteMapping

@PathVariable // /users/{id}
@RequestParam // /users?name=John
@RequestBody // JSON body -> object
@ResponseBody // object -> JSON
@RequestHeader
@CookieValue

@ResponseStatus(HttpStatus.CREATED)
@RestControllerAdvice // Global exception handling
@ExceptionHandler(NotFoundException.class)

@CrossOrigin // CORS
```

### Validation
```java
@Valid // Trigger validation
@NotNull, @NotBlank, @NotEmpty
@Size(min=2, max=50)
@Min, @Max
@Email
@Pattern(regexp="...")
```

### Data / JPA
```java
@Entity
@Table(name="users")
@Id
@GeneratedValue(strategy=GenerationType.IDENTITY)
@Column(name="email", unique=true, nullable=false)
@Transient // Not persisted

@Repository
public interface UserRepository extends JpaRepository<User, Long> {
  Optional<User> findByEmail(String email); // query derivation
  @Query("SELECT u FROM User u WHERE u.age > :age")
  List<User> findByAgeGreaterThan(@Param("age") int age);
  @Modifying @Query("UPDATE User u SET u.active=false WHERE u.id=:id")
  void deactivate(@Param("id") Long id);
}

@Transactional // ACID, propagation, isolation
@Cacheable("users")
@CacheEvict
```

### Configuration
```java
@ConfigurationProperties(prefix="app")
@Component
class AppProperties { String name; int port; }

@PropertySource("classpath:custom.properties")
@Profile("dev") // Bean only for dev profile
@ConditionalOnProperty(name="feature.enabled", havingValue="true")
```

### Scheduling & Async
```java
@EnableScheduling
@Scheduled(fixedRate=5000) // every 5 sec
@Scheduled(cron="0 0 * * * *")

@EnableAsync
@Async // Runs in separate thread pool
```

### Actuator
```java
// Endpoints: /actuator/health, /actuator/metrics, /actuator/info, /actuator/env
management.endpoints.web.exposure.include=health,info,metrics
```

## Spring Boot Core Concepts

### Auto-Configuration
- How it works: `@EnableAutoConfiguration` scans classpath, if Tomcat on classpath configures embedded Tomcat, if H2 on classpath configures DataSource, via `spring.factories` / `AutoConfiguration.imports`
- Disable: `@SpringBootApplication(exclude={DataSourceAutoConfiguration.class})`

### Dependency Injection Types
- Constructor (recommended, immutable, testable, required dependencies)
- Setter (optional dependencies)
- Field (not recommended, hard to test, reflection)

### Bean Lifecycle
1. Instantiate
2. Populate properties (DI)
3. BeanNameAware, BeanFactoryAware
4. @PostConstruct / InitializingBean.afterPropertiesSet
5. Custom init-method
6. Ready to use
7. @PreDestroy / DisposableBean.destroy on shutdown

### Scopes
- Singleton (default, one per container)
- Prototype (new each time, Spring doesn't manage destroy)
- Request (per HTTP request, web only)
- Session (per session)
- Application

### AOP (Aspect Oriented Programming)
- Cross-cutting concerns: Logging, transaction, security
- Concepts: Aspect, Advice (@Before, @After, @Around, @AfterReturning, @AfterThrowing), Pointcut, JoinPoint, Weaving
- Implementation via proxies (JDK dynamic proxy if interface, CGLIB if class)
```java
@Aspect @Component
class LoggingAspect {
  @Around("execution(* com.example.service.*.*(..))")
  public Object log(ProceedingJoinPoint pjp) throws Throwable {
    long start = System.currentTimeMillis();
    Object result = pjp.proceed();
    log.info("Method {} took {} ms", pjp.getSignature(), System.currentTimeMillis()-start);
    return result;
  }
}
```

### Transaction Management
```java
@Transactional(
  propagation=Propagation.REQUIRED, // default, join existing or create new
  isolation=Isolation.READ_COMMITTED,
  rollbackFor=Exception.class,
  readOnly=false,
  timeout=10
)
```
- Propagation: REQUIRED, REQUIRES_NEW (new tx suspends existing), NESTED, SUPPORTS, NOT_SUPPORTED, NEVER, MANDATORY
- Rollback: By default only unchecked exceptions rollback, checked doesn't unless rollbackFor specified

### Spring Security (Quick)
```java
@EnableWebSecurity
@Configuration
class SecurityConfig {
  @Bean SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http.csrf().disable()
      .authorizeHttpRequests(auth -> auth
        .requestMatchers("/api/public/**").permitAll()
        .requestMatchers("/api/admin/**").hasRole("ADMIN")
        .anyRequest().authenticated()
      )
      .oauth2ResourceServer(oauth -> oauth.jwt(...))
      .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS));
    return http.build();
  }
}
```

## Application Properties

```properties
server.port=8080
server.servlet.context-path=/api
spring.datasource.url=jdbc:postgresql://localhost:5432/mydb
spring.datasource.username=user
spring.datasource.password=secret
spring.jpa.hibernate.ddl-auto=validate # none, validate, update, create, create-drop (never update in prod)
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.format_sql=true
spring.cache.type=redis
spring.redis.host=localhost
logging.level.com.example=DEBUG
```

## Profiles

```java
// application-dev.properties, application-prod.properties
// Run with: java -jar app.jar --spring.profiles.active=prod
// Or env: SPRING_PROFILES_ACTIVE=prod
```

## Common Interview Q

**Q: How Spring Boot auto-configuration works internally?**
- @SpringBootApplication includes @EnableAutoConfiguration which imports AutoConfigurationImportSelector that loads META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports files, each auto-config class has @Conditional annotations (OnClass, OnBean, OnProperty) to decide if should configure

**Q: Difference @Component vs @Service vs @Repository?**
- Same as bean but semantics + @Repository has exception translation (converts SQLException to DataAccessException)

**Q: How to handle transactions across microservices?**
- Not via @Transactional (local only), use SAGA pattern

**Q: Spring Boot 2 to 3 migration challenges?**
- Java 17 baseline, javax.* -> jakarta.* (e.g. javax.persistence -> jakarta.persistence), Spring Security 6 config changes (WebSecurityConfigurerAdapter deprecated), Hibernate 6, need to update imports

**Q: How to optimize Spring Boot startup?**
- Lazy initialization `spring.main.lazy-initialization=true`, exclude unnecessary auto-config, use Spring Native GraalVM, reduce component scan scope, async beans
