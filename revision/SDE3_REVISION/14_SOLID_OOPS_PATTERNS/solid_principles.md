# SOLID Principles - SDE3 Must Know with Examples

## S - Single Responsibility Principle (SRP)
- A class should have only one reason to change, one responsibility
- Bad: User class does auth + email + DB save
- Good: UserService, AuthService, EmailService separate
```java
// Bad
class User {
  void save() { /* DB */ }
  void sendEmail() { /* email */ }
}
// Good
class UserRepository { void save(User u) {} }
class EmailService { void send(User u) {} }
```

## O - Open/Closed Principle (OCP)
- Open for extension, closed for modification
- Use abstraction, strategy pattern
```java
// Bad: if-else for each payment type
if (type.equals("UPI")) ...
else if (type.equals("CARD")) ...

// Good: Interface
interface Payment { void pay(); }
class UPIPayment implements Payment { public void pay() {...} }
class CardPayment implements Payment { public void pay() {...} }
// Add new payment without modifying existing code
```

## L - Liskov Substitution Principle (LSP)
- Subtype must be substitutable for parent without breaking
- Child should not break parent contract
```java
// Bad: Square extends Rectangle overriding setWidth/setHeight breaks
// Good: Use interface Shape with area()
interface Shape { double area(); }
class Rectangle implements Shape { ... }
class Square implements Shape { ... }
```
- Example violation: Throwing UnsupportedOperationException in child

## I - Interface Segregation Principle (ISP)
- No client should be forced to depend on methods it doesn't use
- Split fat interfaces into smaller
```java
// Bad
interface Worker { void work(); void eat(); void sleep(); }
class Robot implements Worker { void eat() { throw ... } } // robot doesn't eat

// Good
interface Workable { void work(); }
interface Eatable { void eat(); }
class Human implements Workable, Eatable { ... }
class Robot implements Workable { ... }
```

## D - Dependency Inversion Principle (DIP)
- High-level modules should not depend on low-level, both depend on abstraction
- Depend on interface not concrete class
```java
// Bad: High-level depends on low-level directly
class OrderService {
  MySQLDatabase db = new MySQLDatabase(); // tight coupling
}

// Good: Depend on abstraction
interface Database { void save(); }
class MySQLDatabase implements Database { ... }
class OrderService {
  Database db; // injected via constructor
  OrderService(Database db) { this.db = db; }
}
// Can inject Postgres, Mongo, Mock for testing
```

## Other Principles

### DRY - Don't Repeat Yourself
- Extract common code to function/service

### KISS - Keep It Simple Stupid
- Simple solution over clever complex

### YAGNI - You Aren't Gonna Need It
- Don't build features you don't need yet

### Composition over Inheritance
- Prefer has-a over is-a, more flexible

## Interview Q: Example of SOLID violation you fixed?
"Had a God class OrderService doing payment, inventory, email, DB. Refactored to SRP - split into OrderService, PaymentService, InventoryService, NotificationService. Used DIP with interfaces for DB, OCP with strategy for payment types, improved testability."

## Benefits
- Maintainable, testable, flexible, less coupling, high cohesion
