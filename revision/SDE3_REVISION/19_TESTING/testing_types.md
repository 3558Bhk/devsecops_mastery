# Testing - SDE3 Complete Revision

## Testing Pyramid

```
      E2E (10%) - Slow, expensive, brittle, high confidence
    Integration (20%) - Medium
  Unit (70%) - Fast, cheap, many, low confidence alone
```

- More unit tests, fewer E2E
- SDE3 should focus on pyramid not ice-cream cone (many E2E few unit is anti-pattern)

## Types of Testing

### 1. Unit Testing
- Test single class/method in isolation, mock dependencies
- Fast, no DB, no network
- Tools: JUnit 5, Mockito, Jest, Pytest
```java
@ExtendWith(MockitoExtension.class)
class UserServiceTest {
  @Mock UserRepository repo;
  @InjectMocks UserService service;

  @Test
  void shouldReturnUserWhenExists() {
    when(repo.findById(1L)).thenReturn(Optional.of(new User(1L, "John")));
    User result = service.getUser(1L);
    assertEquals("John", result.getName());
    verify(repo).findById(1L);
  }

  @Test
  void shouldThrowWhenNotFound() {
    when(repo.findById(1L)).thenReturn(Optional.empty());
    assertThrows(NotFoundException.class, () -> service.getUser(1L));
  }
}
```
- AAA pattern: Arrange, Act, Assert
- Coverage: Aim 80% for critical paths, 100% not needed, focus on business logic

### 2. Integration Testing
- Test interaction between components: Service + DB, Service + API
- Slower, needs DB (Testcontainers) or real service
- Tools: Testcontainers, SpringBootTest, Supertest
```java
@SpringBootTest
@Testcontainers
class UserRepositoryTest {
  @Container static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15");
  @Autowired UserRepository repo;

  @Test
  void shouldSaveAndFind() {
    User user = new User("John","a@b.com");
    repo.save(user);
    Optional<User> found = repo.findByEmail("a@b.com");
    assertTrue(found.isPresent());
  }
}
```

### 3. E2E / Functional Testing
- Test full flow from UI to DB, like user
- Tools: Selenium, Cypress, Playwright, RestAssured for API E2E
```java
// RestAssured API E2E
given().contentType(JSON).body(newUser)
.when().post("/api/users")
.then().statusCode(201).body("name", equalTo("John"));
```

### 4. Other Types

- **Contract Testing**: Consumer-driven, Pact - ensures API provider doesn't break consumer, important for microservices
- **Performance Testing**: Load (expected load), Stress (beyond capacity to find breaking point), Soak (long duration to find leaks), Spike (sudden spike)
  - Tools: JMeter, k6, Gatling, Locust
- **Security Testing**: OWASP ZAP, Burp Suite, dependency scanning
- **Smoke Testing**: Basic sanity after deploy, does app start, health check
- **Regression Testing**: Ensure new change doesn't break existing
- **Acceptance Testing**: UAT by product owner
- **Mutation Testing**: PIT - mutates code to check if tests catch bugs, measures test quality

## TDD vs BDD

### TDD - Test Driven Development
- Red -> Green -> Refactor
1. Write failing test
2. Write minimal code to pass
3. Refactor
- Benefits: Better design, coverage, confidence
- Use: Complex business logic

### BDD - Behavior Driven Development
- Given-When-Then, business readable
- Tools: Cucumber, JBehave
```gherkin
Given user is logged in
When user adds item to cart
Then cart should contain 1 item
```

## Mocking

### What to Mock?
- External dependencies: DB, API, queue, time, random
- Don't mock: Value objects, entities, simple POJOs

### Mockito Types
- **Mock**: Fake object, no real logic, you stub behavior `when(mock.method()).thenReturn()`
- **Spy**: Wraps real object, real methods called unless stubbed, use for partial mocking
- **Stub**: Predefined responses
- **Fake**: Working implementation but simplified (in-memory DB)

### Verification
```java
verify(repo, times(1)).save(any());
verify(repo, never()).delete(any());
verifyNoMoreInteractions(repo);
```

## Test Best Practices SDE3

1. **FIRST**: Fast, Isolated, Repeatable, Self-validating, Timely
2. **One assert per test?** Not strict but focused tests
3. **Naming**: `shouldReturnUserWhenExists` not `test1`
4. **No logic in tests**: No if-else in test
5. **Independent**: Tests shouldn't depend on order, no shared state
6. **Use builders/factories for test data**: `UserBuilder.aUser().withName("John").build()`
7. **Don't test private methods**: Test via public API
8. **Use in-memory DB for integration**: H2 for JPA but Testcontainers with real PG better (H2 compatibility issues)
9. **Clean up**: @Transactional rollback, or @AfterEach cleanup
10. **Parameterized tests**: Test many inputs
```java
@ParameterizedTest
@ValueSource(strings={"", " ", "  "})
void shouldFailWhenBlank(String input) { ... }

@CsvSource({"1, 1", "2, 4", "3, 9"})
void shouldSquare(int input, int expected) { assertEquals(expected, input*input); }
```

## Code Coverage

- **Line**: % lines executed
- **Branch**: % if-else branches covered
- **Mutation**: % mutants killed
- Tools: JaCoCo (Java), Istanbul (JS), Coverage.py
- Don't chase 100%, focus on critical business logic, 80% good

## CI Integration

```yaml
# GitHub Actions
- run: mvn clean test
- run: mvn jacoco:report
- uses: codecov/codecov-action@v3
```

## Flaky Tests

- Cause: Time dependency, async without await, shared state, randomness, external dependency, order dependency
- Fix: Use fixed clock, awaitility for async, isolate, mock external, no Thread.sleep use await

## Interview Q

**Q: How to test microservices?**
- Unit: Mock dependencies
- Integration: Testcontainers for DB, WireMock for external API mock
- Contract: Pact consumer-driven
- E2E: Test only critical flows, not all, via test env
- Component: Test service in isolation with real dependencies via Docker

**Q: How to test private method?**
- Don't directly, test via public method that calls private, or if complex extract to new class with public method, or make package-private for testing, reflection as last resort

**Q: What is Testcontainers?**
- Library that runs real Docker containers (Postgres, Redis, Kafka) for integration tests, more reliable than H2 or mocks, disposable, ensures prod parity

## Example: Testing Async

```java
// Awaitility
await().atMost(5, SECONDS).until(() -> userRepo.findByEmail("a@b.com").isPresent());
```
