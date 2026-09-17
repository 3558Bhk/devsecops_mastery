# Design Patterns - GoF 23 Patterns - SDE3 Top 12 Must Know

## Creational (5)

### 1. Singleton
- Only one instance globally
- Use: Config manager, Logger, DB connection pool
- Thread-safe implementation
```java
// Double-checked locking + volatile
public class Singleton {
  private static volatile Singleton instance;
  private Singleton() {}
  public static Singleton getInstance() {
    if (instance == null) {
      synchronized (Singleton.class) {
        if (instance == null) instance = new Singleton();
      }
    }
    return instance;
  }
}
// Or Enum - best
public enum Singleton { INSTANCE; }
```
- Issues: Testing hard, hidden dependencies, breaks SRP, consider DI instead

### 2. Factory
- Creates objects without exposing creation logic
- Use: When creation complex or need to decide type at runtime
```java
interface Payment { void pay(); }
class PaymentFactory {
  static Payment create(String type) {
    if ("UPI".equals(type)) return new UPIPayment();
    if ("CARD".equals(type)) return new CardPayment();
    throw new IllegalArgumentException();
  }
}
```

### 3. Abstract Factory
- Factory of factories, creates family of related objects
- Example: UI toolkit - WindowsFactory creates WindowsButton + WindowsCheckbox, MacFactory creates MacButton + MacCheckbox

### 4. Builder
- Build complex object step by step, same construction different representation
- Use: Object with many optional params, telescoping constructor anti-pattern
```java
class User {
  private final String name, email, phone;
  private User(Builder b) { this.name=b.name; this.email=b.email; this.phone=b.phone; }
  static class Builder {
    String name, email, phone;
    Builder name(String n) { this.name=n; return this; }
    Builder email(String e) { this.email=e; return this; }
    User build() { return new User(this); }
  }
}
User u = new User.Builder().name("John").email("a@b.com").build();
```
- Lombok @Builder

### 5. Prototype
- Clone existing object instead of new, expensive creation
- Use: When creation costly, need many similar objects

## Structural (7) - Top 4

### 6. Adapter
- Converts one interface to another expected by client
- Example: Old XML library to new JSON interface, Payment gateway adapter
```java
// Old: XmlService.getDataXml()
// Need: JsonService.getDataJson()
// Adapter: XmlToJsonAdapter implements JsonService, internally calls XmlService and converts
```

### 7. Decorator
- Add behavior dynamically without altering class, wraps object
- Example: Java IO `new BufferedReader(new FileReader(file))`, Spring @Transactional, pizza toppings
```java
interface Coffee { double cost(); }
class SimpleCoffee implements Coffee { public double cost() { return 5; } }
class MilkDecorator implements Coffee {
  Coffee coffee;
  MilkDecorator(Coffee c) { this.coffee=c; }
  public double cost() { return coffee.cost() + 2; }
}
```

### 8. Proxy
- Placeholder to control access to object
- Types: Virtual (lazy load), Protection (access control), Remote (RMI), Caching, Logging
- Use: Lazy initialization, access control, logging, Spring AOP uses proxy
```java
interface Image { void display(); }
class ProxyImage implements Image {
  RealImage real;
  String file;
  ProxyImage(String file) { this.file=file; }
  public void display() {
    if (real==null) real = new RealImage(file); // lazy
    real.display();
  }
}
```

### 9. Facade
- Simplified interface to complex subsystem
- Example: OrderService facade hides PaymentService, InventoryService, NotificationService complexity

## Behavioral (11) - Top 5

### 10. Observer
- One-to-many dependency, when subject changes all observers notified
- Use: Event handling, pub/sub, MVC
- Example: YouTube channel subscribe, Kafka consumers
```java
interface Observer { void update(String msg); }
class Subject {
  List<Observer> observers = new ArrayList<>();
  void subscribe(Observer o) { observers.add(o); }
  void notifyAll(String msg) { observers.forEach(o->o.update(msg)); }
}
```
- Java: Listeners, Spring ApplicationEvent

### 11. Strategy
- Define family of algorithms, encapsulate each, make interchangeable at runtime
- Use: Payment strategies, sorting strategies, compression
```java
interface Strategy { int doOperation(int a, int b); }
class Add implements Strategy { public int doOperation(int a,int b){return a+b;} }
class Context {
  Strategy strategy;
  Context(Strategy s) { this.strategy=s; }
  int execute(int a,int b){ return strategy.doOperation(a,b); }
}
```
- Avoids if-else, follows OCP

### 12. Chain of Responsibility
- Pass request along chain until handled
- Example: Servlet filters, Spring Security filter chain, logging levels, ATM dispenser
```java
abstract class Logger {
  Logger next;
  void setNext(Logger n) { this.next=n; }
  void log(String level, String msg) {
    if (canHandle(level)) write(msg);
    if (next!=null) next.log(level, msg);
  }
}
```

### 13. Additional Important for SDE3
- **Template Method**: Define skeleton in parent, child overrides steps
- **Command**: Encapsulate request as object, undo/redo, queue
- **Iterator**: Traverse collection without exposing internals

## How to Identify Which Pattern in Interview?

- Need one instance -> Singleton
- Complex creation -> Factory/Builder
- Need to add behavior dynamically -> Decorator
- Need to adapt old to new -> Adapter
- Need to simplify complex system -> Facade
- Need to notify many when one changes -> Observer
- Need interchangeable algorithms -> Strategy
- Need to chain handlers -> Chain of Responsibility

## Anti-Patterns to Avoid
- God Object, Spaghetti, Singleton overuse, Premature optimization

## Interview Tip
Don't just define, give real project example:
"In our payment module we used Strategy pattern for different payment gateways (Razorpay, Stripe, PayU) with common interface. Factory to create strategy based on user choice. This followed OCP - adding new gateway didn't modify existing code."
