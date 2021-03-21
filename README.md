[![Swift](https://img.shields.io/badge/swift-5.3-orange.svg?style=flat)](#) [![Build Status](https://travis-ci.org/alexdrone/Store.svg?branch=master)](https://travis-ci.org/alexdrone/Store) [![Cov](https://img.shields.io/badge/coverage-45.8%25-blue.svg?style=flat)](#) [![Platform](https://img.shields.io/badge/platform-macOS%20|%20iOS%20|%20WatchOS%20|%20tvOS%20|%20Linux-red.svg?style=flat)](#)
<img src="https://raw.githubusercontent.com/alexdrone/Dispatch/master/docs/store_logo.png" width=300 alt="Dispatch" align=right />

Unidirectional, transactional, operation-based Store implementation for Swift and SwiftUI

# Overview

Store eschews MVC in favour of a unidirectional data flow. 
When a user interacts with a view, the view propagates an action to a store that hold the 
application's data and business logic, which updates all of the views that are affected.

This works especially well with *SwiftUI*'s declarative programming style, which allows the 
store to send updates without specifying how to transition views between states.

- **Stores**: Holds the state of your application. You can have multiple stores for multiple 
domains of your app.
- **Actions**: You can only perform state changes through actions. 
Actions are small pieces of data (typically *enums* or *structs*) that describe a state change. 
By drastically limiting the way state can be mutated, your app becomes easier to understand and 
it gets easier to work with many collaborators.
- **Views**: A simple function of your state. This works especially well with *SwiftUI*'s 
declarative programming style.

# Getting started

TL;DR

Yet another counter:

```swift
import SwiftUI
import Store

struct CounterModel { var count: Int }

struct CounterView: View {
  @ObservedObject var store = Store(model: CounterModel(count: 0))
  
  var body: some View {
    VStack {
      Text(String(describing: store.binding.count))
      HStack {
        Button("Increase") { store.binding.count += 1 }
        Button("Decrease") { store.binding.count -= 1 }
      }
    }
  }
}
```

Yet another todo list:

```swift
final class Todo: Codable, Identifiable {
  let id = PushID.default.make()
  var text: String = "Untitled Todo"
  var done: Bool = false
}

final class TodoList: Codable {
  var todos: [Todo] = []
}

extension Store where M == TodoList {
  func addNewTodo() {
    mutate { $0.todos.append(Todo()) }
  }
  func move(from source: IndexSet, to destination: Int) {
    mutate { $0.todos.move(fromOffsets: source, toOffset: destination) }
  }
  func remove(todo: Todo) {
    mutate { model in 
      model.todos = model.todos.filter { $0.id != todo.id } 
    }
  }
}

// MARK: - Views

struct TodoView: View {
  @ObservedObject var store: CodableStore<Todo>
  let onRemove: () -> Void
  
  var body: some View {
    HStack {
      // Move handle.
      Image(systemName: "line.horizontal.3")
      // Text.
      if store.readOnlyModel.done {
        Text(store.readOnlyModel.text).strikethrough()
      } else {
        TextField("Todo", text: $store.binding.text)
      }
      Spacer()
      // Mark item as done.
      Toggle("", isOn: $store.binding.done)
      // Remove task.
      Button("Remove", action: onRemove)
    }.padding()
  }
}

struct TodoListView: View {
  @ObservedObject var store = CodableStore(model: TodoList())
  
  var body: some View {
    List {
      // Todo items.
      ForEach(store.readOnlyModel.todos) { todo in
        TodoView(store: CodableStore(model: todo)) { store.remove(todo: todo) }
      }
      .onMove(perform: store.move)
      // Add a new item.
      Button("New Todo", action: store.addNewTodo)
    }
  }
}
```


### Store

Stores contain the application state and logic. Their role is somewhat similar to a model in a 
traditional MVC, but they manage the state of many objects — they do not represent a single record
of data like ORM models do. More than simply managing a collection of ORM-style objects, stores 
manage the application state for a particular domain within the application.

This allows an action to result in an update to the state of the store. 
After the stores are updated, they notify the observers that their state has changed,
so the views may query the new state and update themselves.

```swift
struct Counter { var count = 0 }
let store = Store<Counter>(model: Counter())
```

### Actions

An action represent an operation on the store that is cancellable and is performed transactionally
on the Store.

Actions can be defined using an enum or a struct.

```swift
enum CounterAction: Action {
  case increase
  case decrease

  func mutate(context: TransactionContext<Store<Counter>, Self>) {
    defer {
      // Remember to always call `fulfill` to signal the completion of this operation.
      context.fulfill()
    }
    switch self {
    case .increase(let amount):
      context.update { $0.count += 1 }
    case .decrease(let amount):
      context.update { $0.count -= 1 }
    }
  }
  
  func cancel(context: TransactionContext<Store<Counter>, Self>) { }
}
```

```swift
struct IncreaseAction: Action {
  let count: Int

  func mutate(context: TransactionContext<Store<Counter>, Self>) {
    defer {
      // Remember to always call `fulfill` to signal the completion of this operation.
      context.fulfill()
    }
    context.mutate { $0.count += 1 }
  }
  
  func cancel(context: TransactionContext<Store<Counter>, Self>) { }
}
```

Alternatively using a binding to change the store value (through `store.binding`) or calling 
`store.mutate { model in }` would implicitly create and run an action that is performed synchronously.

```
Button("Increase") { store.binding.count += 1 }
```

#  Documentation

### `class Store<M>: ObservableObject, Identifiable`

This class is the default implementation of the `MutableStore` protocol.
A store wraps a value-type model, synchronizes its mutations, and emits notifications to its
observers any time the model changes.

Model mutations are performed through `Action`s: These are operation-based, cancellable and
abstract the concurrency execution mode.
Every invokation of `run(action:)` spawns a new transaction object that can be logged,
rolled-back and used to inspect the model diffs (see `TransactionDiff`).

It's recommendable not to define a custom subclass (you can use `CodableStore` if you want
diffing and store serialization capabilities).
Domain-specific functions can be added to this class by writing an extension that targets the
user-defined model type.
e.g.
```swift
 let store = Store(model: Todo())
 [...]
 extension Store where M == Todo {
   func upload() -> Future<Void, Error> {
     run(action: TodoAction.uploadAndSynchronizeTodo, throttle: 1)
   }
 }
 ```
 
 ### Model

* `let modelStorage: M`
 The associated storage for the model (typically a value type).
 
 * `let binding: BindingProxy<M>`
 Read-write access to the model through `@Binding` in SwiftUI.
 e.g.
 `Toggle("...", isOn: $store.binding.someProperty)`.
 When the binding set a new value an implicit action is being triggered and the property is
 updated.


 ### Observation
 
 * `func notifyObservers()`
Notify the store observers for the change of this store.
`Store` and `CodableStore` are `ObservableObject`s and they automatically call this
function (that triggers a `objectWillChange` publlisher) every time the model changes.
Note: Observers are always scheduled on the main run loop.
 
* `func performWithoutNotifyingObservers(_ perform: () -> Void)`
The block passed as argument does not trigger any notification for the Store observers.
e.g. By calling `reduceModel(transaction:closure:)` inside the `perform` block the store
won't pubblish any update.

### Combine Stores

 
* `func makeChildStore<C>(keyPath: WritableKeyPath<M, C>) -> Store<C>`
Used to express a parent-child relationship between two stores.
This is the case when it is desired to have a store (child) to manage to a subtree of 
the store (parent) model.
`CombineStore` define a merge strategy to reconcile back the changes from the child to the parent.
 e.g.
 ```swift
struct Model { let items: [Item] }
let store = Store(model: Model())
 let child = store.makeChildStore(keyPath: \.[0])
 ```

### Transactions

* `func transaction<A: Action, M>( action: A, mode: Executor.Strategy = default) -> Transaction<A>`
Builds a transaction object for the action passed as argument.
This can be executed by calling the `run` function on it.
Transactions can depend on each other's completion by calling the `depend(on:)` function.
 e.g.
 ```swift
let t1 = store.transaction(.addItem(cost: 125))
let t2 = store.transaction(.checkout)
let t3 = store.transaction(.showOrdern)
t2.depend(on: [t1])
t3.depend(on: [t2])
[t1, t2, t3].run()
```

### Running Actions

* `func run<A: Action, M>(action: A, mode: Executor.Strategy = default, throttle: TimeInterval = default) -> Future<Void, Error> `
Runs the action passed as argument on this store and returns a future that is resolved when the 
action execution has completed.

* `func run<A: Action, M>(actions: [A], mode: Executor.Strategy = default) -> Future<Void, Error> `
Runs all of the actions passed as argument sequentially.
This means that `actions[1]` will run after `actions[0]` has completed its execution, 
`actions[2]` after `actions[1]` and so on.

### Middleware

* `func register(middleware: Middleware)`
Register a new middleware service.
Middleware objects are notified whenever a transaction running in this store changes its state.

* `func unregister(middleware: Middleware)`
Unregister a middleware service.

### `class CodableStore<M: Codable>: Store<M>`

A `Store` subclass with serialization capabilities.
Additionally a `CodableStore` can emits diffs for every transaction execution (see
the `lastTransactionDiff` pubblisher).
This can be useful for store synchronization (e.g. with a local or remote database).

* `static func encode<V: Encodable>(model: V) -> EncodedDictionary`
Encodes the model into a dictionary.

* `static func encodeFlat<V: Encodable>(model: V) -> FlatEncoding.Dictionary`
Encodes the model into a flat dictionary.
The resulting dictionary won't be nested and all of the keys will be paths.
e.g. `{user: {name: "John", lastname: "Appleseed"}, tokens: ["foo", "bar"]`
turns into
```json
{
   user/name: "John",
   user/lastname: "Appleseed",
   tokens/0: "foo",
   tokens/1: "bar"
 } 
 ```
 This is particularly useful to synchronize the model with document-based databases
(e.g. Firebase).

# Demos

* [HackerNews Client](https://github.com/alexdrone/Store/tree/master/Demo/store_hacker_news)
<img src="https://raw.githubusercontent.com/alexdrone/Dispatch/master/docs/store_hacker_news_demo.gif" width=600 alt="hacker_news_demo" align=center />

# Cookbook

A collection of Store usage scenarios.

## Serialization and Diffing

TL;DR

```swift
struct MySerializableModel: Codable {
var count = 0
var label = "Foo"
var nullableLabel: String? = "Bar"
var nested = Nested()
var array: [Nested] = [Nested(), Nested()]
  struct Nested: Codable {
  var label = "Nested struct"
  }
}

let store = SerializableStore(model: TestModel(), diffing: .async)
store.$lastTransactionDiff.sink { diff in
  // diff is a `TransactionDiff` obj containing all of the changes that the last transaction has applied to the store's model.
}
```
A quick look at the  `TransactionDiff` interface:

```swift
public struct TransactionDiff {
  /// The set of (`path`, `value`) that has been **added**/**removed**/**changed**.
  ///
  /// e.g. ``` {
  ///   user/name: <added ⇒ "John">,
  ///   user/lastname: <removed>,
  ///   tokens/1:  <changed ⇒ "Bar">,
  /// } ```
  public let diffs: [FlatEncoding.KeyPath: PropertyDiff]
  /// The identifier of the transaction that caused this change.
  public let transactionId: String
  /// The action that caused this change.
  public let actionId: String
  /// Reference to the transaction that cause this change.
  public var transaction: AnyTransaction
  /// Returns the `diffs` map encoded as **JSON** data.
  public var json: Data
}

/// Represent a property change.
/// A change can be an **addition**, a **removal** or a **value change**.
public enum PropertyDiff {
  case added(new: Codable?)
  case changed(old: Codable?, new: Codable?)
  case removed
}
```

Diff output:

```
▩ INFO (-LnpwxkPuE3t1YNCPjjD) UPDATE_LABEL [0.045134 ms]
▩ DIFF (-LnpwxkPuE3t1YNCPjjD) UPDATE_LABEL {
    · label: <changed ⇒ (old: Foo, new: Bar)>,
    · nested/label: <changed ⇒ (old: Nested struct, new: Bar)>,
    · nullableLabel: <removed>
  }
```

## Combining Stores

As your app logic grows could be convient to split store into smaller one, still using the 
same root model.
This can be achieved by using the `makeChildStore(keyPath:)` API.

```swift
struct App {
  struct Todo {
    var name: String = "Untitled"
    var description: String = "N/A"
    var done: Bool = false
  }
  var todos: [Todo] = []
}

// This action targets a Store<Todo>...
struct TodoActionMarkAsDone: Action {
  func reduce(context: TransactionContext<Store<App.Todo>, Self>) {
    defer { context.fulfill() }
    context.reduceModel { $0.done = true }
  }
}

// ..While this one the whole collection Store<[Todo]>
struct TodoListActionCreateNew: Action {
  let name: String
  let description: String
  func reduce(context: TransactionContext<Store<Array<App.Todo>>, Self>) {
    defer { context.fulfill() }
    let new = Root.Todo(name: name, description: description)
    context.reduceModel {
      $0.append(new)
    }
  }
}

let appModel = App()
let rootStore = Store(model: appModel)

let todoListStore = rootStore.makeChildStore(keyPath: \.todos)
todoListStore.run(action: TodoListActionCreateNew(name: "New", decription: "New"), mode: .sync)

let todoStore = rootStore.makeChildStore(keyPath: \.[0])
todoStore.run(action: TodoActionMarkAsDone(), mode: .sync)
```

This is a good strategy to prevent passing down the whole application store as a dependency 
when not needed 
_(e.g. maybe your datasource just need the TodoList store and your cell the single-value Todo store)._ 

## Advanced

Dispatch takes advantage of *Operations* and *OperationQueues* and you can define 
complex dependencies between the operations that are going to be run on your store.


### Chaining actions

```swift
store.run(actions: [
  CounterAction.increase(amount: 1),
  CounterAction.increase(amount: 1),
  CounterAction.increase(amount: 1),
]) { context in
  // Will be executed after all of the transactions are completed.
}
```
Actions can also be executed in a synchronous fashion.

```swift
store.run(action: CounterAction.increase(amount: 1), strategy: .mainThread)
store.run(action: CounterAction.increase(amount: 1), strategy: .sync)
```

### Complex Dependencies

You can form a dependency graph by manually constructing your transactions and use
the `depend(on:)` method.

```swift
let t1 = store.transaction(.addItem(cost: 125))
let t2 = store.transaction(.checkout)
let t3 = store.transaction(.showOrdern)
t2.depend(on: [t1])
t3.depend(on: [t2])
[t1, t2, t3].run()
```

### Throttling transactions

Transactions can express a throttle delay.

```swift
func calledOften() {
  store.run(.myAction, throttle: 0.5)
}
```

### Tracking a transaction state

Sometimes it's useful to track the state of a transaction (it might be useful to update the 
UI state to reflect that).

```swift
store.run(action: CounterAction.increase(amount: 1)).$state.sink { state in
  switch(state) {
  case .pending: ...
  case .started: ...
  case .completed: ...
  }
}
```

### Checking the diff state of a specific property after a transaction

```swift
sink = store.$lastTransactionDiff.sink { diff in
  diff.query { $0.path.to.my.property }.isChanged() // or .isRemoved(), .isAdded()
}
```

### Dealing with errors

```swift
struct IncreaseAction: Action {
  let count: Int

  func reduce(context: TransactionContext<Store<Counter>, Self>) {
    // Remember to always call `fulfill` to signal the completion of this operation.
    defer { context.fulfill() }
    // The operation terminates here because an error has been raised in this dispatch group.
    guard !context.rejectOnPreviousError() { else return }
    // Kill the transaction and set TransactionGroupError.lastError.
    guard store.model.count != 42 { context.reject(error: Error("Max count reach") }
    // Business as usual...
    context.reduceModel { $0.count += 1 }
  }
}
```

### Cancellation

```swift
let cancellable: AnyCancellable = store.run(action: CounterAction.increase(amount: 1)).eraseToAnyCancellable();
cancellable.cancel()
```

```
▩ 𝙄𝙉𝙁𝙊 (-Lo4riSWZ3m5v1AvhgOb) INCREASE [✖ canceled]
```
