# Hibernate / JPA - Quick Revision

## JPA vs Hibernate
- JPA: Specification (interface), javax/jakarta.persistence
- Hibernate: Implementation of JPA, most popular, extra features

## Entity Lifecycle
- Transient: New object not associated with session, no ID in DB
- Persistent: Associated with session, changes tracked, will be saved
- Detached: Was persistent but session closed, changes not tracked
- Removed: Scheduled for deletion

## Annotations

```java
@Entity @Table(name="users")
class User {
  @Id @GeneratedValue(strategy=IDENTITY) Long id;
  @Column(unique=true, nullable=false, length=100) String email;
  @Enumerated(EnumType.STRING) Role role;
  @Temporal(TemporalType.TIMESTAMP) Date createdAt; // old, use LocalDateTime now
  @Lob String bigText;
  @Transient String temp; // not persisted
  @CreationTimestamp LocalDateTime createdAt; // Hibernate
  @UpdateTimestamp LocalDateTime updatedAt;
}

@OneToMany(mappedBy="user", cascade=CascadeType.ALL, fetch=FetchType.LAZY)
List<Order> orders;

@ManyToOne(fetch=LAZY) @JoinColumn(name="user_id")
User user;

@ManyToMany
@JoinTable(name="user_roles", joinColumns=@JoinColumn(name="user_id"), inverseJoinColumns=@JoinColumn(name="role_id"))
Set<Role> roles;

@OneToOne
```

## Fetch Types

| FetchType | When loads | Use |
|-----------|------------|-----|
| EAGER | Immediately with parent, JOIN | Bad for collections, N+1, use for ManyToOne single |
| LAZY | On first access, proxy, needs open session | Default for collections, good, but need handle LazyInitializationException |

- **LazyInitializationException**: Access lazy collection after session closed, fix: JOIN FETCH in query, or @EntityGraph, or Open Session in View (anti-pattern, disable `spring.jpa.open-in-view=false`)

## N+1 Problem

```java
// Bad: 1 query for users + N queries for orders
List<User> users = userRepo.findAll();
for (User u : users) { u.getOrders().size(); } // N queries

// Fix 1: JOIN FETCH
@Query("SELECT u FROM User u LEFT JOIN FETCH u.orders")
List<User> findAllWithOrders();

// Fix 2: EntityGraph
@EntityGraph(attributePaths={"orders"})
List<User> findAll();

// Fix 3: Batch size
@BatchSize(size=20) // loads 20 collections in one query
List<Order> orders;
```

## Cascade Types
- ALL, PERSIST, MERGE, REMOVE, REFRESH, DETACH
- ALL includes all, but careful with REMOVE may delete child unintentionally

## Inheritance Strategies

```java
@Inheritance(strategy=InheritanceType.SINGLE_TABLE) // one table with discriminator, fast but nullable columns
@Inheritance(strategy=JOINED) // separate tables joined, normalized but slow joins
@Inheritance(strategy=TABLE_PER_CLASS) // table per concrete class, union, bad polymorphic queries
```

## Caching

### First Level Cache
- Session level, mandatory, per session, same object returned within session, cleared on session close

### Second Level Cache
- SessionFactory level, shared across sessions, needs config (EhCache, Redis)
- `@Cacheable @Cache(usage=CacheConcurrencyStrategy.READ_WRITE)`
- Use for reference data rarely changed

### Query Cache
- Caches query results, needs second level cache enabled
- `query.setCacheable(true)`

## Dirty Checking
- Hibernate tracks changes to persistent entities, at flush time auto generates UPDATE for changed fields, no need explicit save

## Flush Modes
- AUTO (default, flush before query), COMMIT, ALWAYS, MANUAL

## Transactions & Isolation already covered

## Best Practices

1. Use LAZY for collections, EAGER for ManyToOne optional
2. Avoid N+1 with JOIN FETCH or EntityGraph
3. Use DTO projections for read-only queries instead of entities (faster)
```java
interface UserDto { String getName(); String getEmail(); }
@Query("SELECT u.name as name, u.email as email FROM User u")
List<UserDto> findDto();
```
4. Batch inserts: `spring.jpa.properties.hibernate.jdbc.batch_size=50` + `order_inserts=true`
5. Use `saveAll()` with batch
6. Don't use `EAGER` everywhere
7. Validate with `spring.jpa.hibernate.ddl-auto=validate` in prod, never update
8. Use Flyway/Liquibase for migrations, not auto DDL
9. Pagination with `Pageable`, but for large offset use keyset pagination (seek method) `WHERE id > lastId LIMIT 20` faster than OFFSET
10. Use `@Version` for optimistic locking to prevent lost updates

```java
@Entity
class Product {
  @Version Long version; // optimistic locking
}
// If two transactions update same product, one fails with OptimisticLockException, retry
```

## Interview Q

**Q: Difference get vs load?**
- get: Immediate DB hit, returns null if not found
- load: Returns proxy, lazy, throws ObjectNotFoundException if not found when accessed, deprecated in Hibernate 6 use getReference

**Q: save vs persist vs merge?**
- save (Hibernate): Returns ID, outside transaction can be called, immediate insert may happen
- persist (JPA): Void, must be in transaction, may delay insert, doesn't return ID
- merge: For detached entity, copies state to persistent, returns managed entity, for update
- saveOrUpdate: Deprecated

**Q: How to handle large data?**
- Pagination, streaming `Stream<User> streamAll()`, batch processing, ScrollableResults, stateless session
