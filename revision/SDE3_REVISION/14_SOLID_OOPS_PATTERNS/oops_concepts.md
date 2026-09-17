# OOPS Concepts - SDE3 Deep Revision

## 4 Pillars

### 1. Encapsulation
- Bundling data + methods, hiding internal details, expose via public methods
- Access modifiers: private, protected, public, default
- Getter/Setter with validation
- Benefit: Control, security, maintainability
```java
class User {
  private String password; // hide
  public void setPassword(String pwd) {
    if (pwd.length() < 8) throw new IllegalArgumentException();
    this.password = BCrypt.hashpw(pwd);
  }
}
```

### 2. Abstraction
- Hiding complexity, showing only essential features
- Achieved via abstract class and interface
- Abstract class can have state + constructor + concrete methods, interface (Java 8+) can have default/static, Java 9+ private
- When use what? Abstract when is-a relationship with shared state, interface for can-do capability, multiple inheritance

### 3. Inheritance
- Child reuses parent properties
- Types: Single, multilevel, hierarchical, multiple (via interface in Java), hybrid
- Super keyword, method overriding
- Diamond problem solved via interfaces in Java
- Composition vs Inheritance: Prefer composition for flexibility

### 4. Polymorphism
- Many forms, same interface different behavior

#### Compile-time (Static) - Method Overloading
- Same method name different params, resolved at compile time
```java
class Calc { int add(int a, int b) {return a+b;} double add(double a, double b) {return a+b;} }
```

#### Runtime (Dynamic) - Method Overriding
- Child overrides parent method, resolved at runtime via dynamic dispatch
```java
class Animal { void sound() { System.out.println("..."); } }
class Dog extends Animal { void sound() { System.out.println("Bark"); } }
Animal a = new Dog(); a.sound(); // Bark - runtime polymorphism
```

## Other Important OOPS

### Association, Aggregation, Composition
- **Association**: Uses-a, loose coupling (Teacher uses Student)
- **Aggregation**: Has-a, weak ownership, child can exist without parent (Department has Teachers, if dept deleted teachers still exist)
- **Composition**: Has-a, strong ownership, child cannot exist without parent (House has Rooms, house deleted rooms deleted)

### Abstract Class vs Interface (Java 8+ vs 17+)

| Feature | Abstract Class | Interface |
|---------|---------------|-----------|
| State | Can have instance vars | Only public static final (Java 8), private allowed 9+ |
| Constructor | Yes | No |
| Methods | Abstract + concrete | Abstract + default + static |
| Inheritance | Single extends | Multiple implements |
| When | is-a + shared code | can-do + contract |

### Method Overloading vs Overriding

| Overloading | Overriding |
|-------------|------------|
| Same class | Parent-child |
| Different params | Same signature |
| Compile time | Runtime |
| Return type can differ | Return type covariant |
| Increases readability | Provides specific impl |

### Coupling & Cohesion
- **Low Coupling High Cohesion** is goal
- Coupling: Degree of dependency between modules (tight vs loose)
- Cohesion: How related methods inside class are (high cohesion = single focused purpose)

### Immutable Class
- Final class, private final fields, no setters, constructor sets all, defensive copy for mutable fields, no subclass
```java
final class ImmutableUser {
  private final String name;
  private final List<String> roles;
  ImmutableUser(String name, List<String> roles) {
    this.name = name;
    this.roles = new ArrayList<>(roles); // defensive copy
  }
  public String getName() { return name; }
  public List<String> getRoles() { return Collections.unmodifiableList(roles); }
}
```
- Benefits: Thread safe, no side effects, good for cache keys, String is immutable

### Object Class Methods (Java)
- toString, equals, hashCode, getClass, clone, finalize (deprecated)
- Always override equals + hashCode together contract

### SOLID already covered, but OOPS interview tip
- Be ready to design with OOPS: e.g. Parking Lot uses encapsulation, inheritance (Vehicle -> Car/Bike), polymorphism (calculateFee)

## Common Interview Q

**Q: Why composition over inheritance?**
- Inheritance breaks encapsulation (child depends on parent impl), tight coupling, fragile base class, inflexible at runtime. Composition flexible, testable via DI.

**Q: Diamond problem?**
- Multiple inheritance of classes causes ambiguity which parent method. Java solves by not allowing multiple class extends, only multiple interfaces with default methods need override to resolve.

**Q: Can you override static method?**
- No, static method hiding not overriding, resolved at compile time based on reference type.

**Q: What is object slicing?**
- C++ issue not Java.
