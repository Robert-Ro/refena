# Riverpie

[![pub package](https://img.shields.io/pub/v/riverpie.svg)](https://pub.dev/packages/riverpie)
![ci](https://github.com/Tienisto/riverpie/actions/workflows/ci.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A state management library for Dart and Flutter. Inspired by [Riverpod](https://pub.dev/packages/riverpod).

## Preview

Define a provider:

```dart
final counterProvider = NotifierProvider<Counter, int>((ref) => Counter());

class Counter extends Notifier<int> {
  @override
  int init() => 10;

  void increment() => state++;
}
```

Use `context.ref` to access the provider:

```dart
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final myValue = ref.watch(counterProvider);
    return Scaffold(
      body: Center(
        child: Text('The value is $myValue'),
      ),
    );
  }
}
```

## Table of Contents

- [Riverpie vs Riverpod](#riverpie-vs-riverpod)
    - [Key differences](#-key-differences)
    - [Similarities](#-similarities)
- [Getting Started](#getting-started)
- [Access the state](#access-the-state)
- [Providers](#providers)
    - [Provider](#-provider)
    - [FutureProvider](#-futureprovider)
    - [StateProvider](#-stateprovider)
    - [NotifierProvider](#-notifierprovider)
    - [AsyncNotifierProvider](#-asyncnotifierprovider)
    - [ReduxProvider](#-reduxprovider)
    - [ViewProvider](#-viewprovider)
- [Notifiers](#notifiers)
    - [Notifier](#-notifier)
    - [AsyncNotifier](#-asyncnotifier)
    - [PureNotifier](#-purenotifier)
    - [ReduxNotifier](#-reduxnotifier)
- [Using ref](#using-ref)
    - [ref.read](#-refread)
    - [ref.watch](#-refwatch)
    - [ref.stream](#-refstream)
    - [ref.future](#-reffuture)
    - [ref.notifier](#-refnotifier)
    - [ref.redux](#-refredux)
- [What to choose?](#what-to-choose)
- [Performance Optimization](#performance-optimization)
- [ensureRef](#ensureref)
- [defaultRef](#defaultref)
- [Observer](#observer)
- [Testing](#testing)
    - [Override providers](#-override-providers)
    - [Testing without Flutter](#-testing-without-flutter)
    - [Testing ReduxProvider](#-testing-reduxprovider)
    - [Access the state within tests](#-access-the-state-within-tests)
    - [State events](#-state-events)
    - [Example test](#-example-test)
- [Dart only](#dart-only)

## Riverpie vs Riverpod

Riverpie is aimed to be more pragmatic and more notifier focused than Riverpod.

### ➤ Key differences

**Flutter native**:\
No `ConsumerWidget` or `ConsumerStatefulWidget`. You still use `StatefulWidget` or `StatelessWidget` as usual.
To access `ref`, you can either use `with Riverpie` (only in `StatefulWidget`) or `context.ref`.

**ref.watch**:\
Providers cannot `watch` other providers. Instead, you can only access other providers with `ref.read` or `ref.notifier`.
The only provider that can `watch` is the `ViewProvider`. This provider is intended to be used as a "view model".
Don't worry that you unintentionally use `watch` inside providers because each `ref` is typed accordingly.

**Common super class**:\
`WatchableRef` extends `Ref`. You can use `Ref` as parameter to implement util functions that need access to `ref`.

**Use ref anywhere, anytime**:\
Don't worry that the `ref` within providers or notifiers becomes invalid.
They live as long as the `RiverpieScope`.
With `ensureRef`, you also can access the `ref` within `initState` or `dispose`.

**No provider modifiers**:\
There is no `.family` or `.autodispose`. This makes the provider landscape simple and straightforward.

**Notifier first**:\
With `Notifier`, `AsyncNotifier`, `PureNotifier`, and `ReduxNotifier`,
you can choose the right notifier for your use case.

### ➤ Similarities

**Testable**:\
The state is still bound to the `RiverpieScope` widget. This means that you can override every provider in your tests.

**Type-safe**:\
Every provider is correctly typed. Enjoy type-safe auto completions when you read them.

**Auto register**:\
You don't need to register any provider. They will be initialized lazily when you access them.

## Getting started

**Step 1: Add dependency**

```yaml
# pubspec.yaml
dependencies:
  riverpie_flutter: <version>
```

**Step 2: Add RiverpieScope**

```dart
void main() {
  runApp(
    RiverpieScope(
      child: const MyApp(),
    ),
  );
}
```

**Step 3: Define a provider**

```dart
final myProvider = Provider((_) => 42);
```

**Step 4: Use the provider**

```dart
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final myValue = context.ref.watch(myProvider);
    return Scaffold(
      body: Center(
        child: Text('The value is $myValue'),
      ),
    );
  }
}
```

## Access the state

The state should be accessed via `ref`.

You can get the `ref` right from the `context`:

```dart
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final myValue = ref.watch(myProvider);
    final mySecondValue = ref.watch(mySecondProvider);
    return Scaffold(
      body: Column(
        children: [
          Text('The value is $myValue'),
          Text('The second value is $mySecondValue'),
        ],
      ),
    );
  }
}
```

In a `StatefulWidget`, you can use `with Riverpie` to access the `ref` directly.

```dart
class MyPage extends StatefulWidget {
  @override
  State<MyPage> createState() => _CounterState();
}

class _MyPageState extends State<MyPage> with Riverpie {
  @override
  Widget build(BuildContext context) {
    final myValue = ref.watch(myProvider);
    return Scaffold(
      body: Center(
        child: Text('The value is $myValue'),
      ),
    );
  }
}
```

You can also use `Consumer` to access the state. This is useful to rebuild only a part of the widget tree:

```dart
class MyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref) {
        final myValue = ref.watch(myProvider);
        return Scaffold(
          body: Center(
            child: Text('The value is $myValue'),
          ),
        );
      },
    );
  }
}
```

## Providers

There are many types of providers. Each one has its own purpose.

The most important ones are `Provider` and `NotifierProvider` because they are the most flexible.

| Provider                | Usage                               | Notifier API   | Can `watch` |
|-------------------------|-------------------------------------|----------------|-------------|
| `Provider`              | For constants or stateless services | -              | No          |
| `FutureProvider`        | For immutable async values          | -              | No          |
| `StateProvider`         | For simple states                   | `setState`     | No          |
| `NotifierProvider`      | For regular services                | Custom methods | No          |
| `AsyncNotifierProvider` | For services that need futures      | Custom methods | No          |
| `ReduxProvider`         | For event based services            | Event based    | No          |
| `ViewProvider`          | For view models                     | -              | Yes         |

### ➤ Provider

Use this provider for immutable values (constants or stateless services).

```dart
final myProvider = Provider((ref) => 42);
```

You may initialize this during app start.\
The override order is important:
An exception will be thrown on app start if you reference a provider that is not yet initialized.\
If you have at least one future override, you should await the initialization with `ref.ensureOverrides()`.

```dart
final persistenceProvider = Provider<PersistenceService>((ref) => throw 'Not initialized');
final apiProvider = Provider<ApiService>((ref) => throw 'Not initialized');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final scope = RiverpieScope(
    overrides: [
      // order is important
      persistenceProvider.overrideWithFuture((ref) async {
        final prefs = await SharedPreferences.getInstance();
        return PersistenceService(prefs);
      }),
      apiProvider.overrideWithFuture((ref) async {
        final persistenceService = ref.read(persistenceProvider);
        final anotherService = await initAnotherService();
        return ApiService(persistenceService, anotherService);
      }),
    ],
    child: const MyApp(),
  );

  await scope.ensureOverrides();

  runApp(scope);
}
```

To access the value:

```dart
// Everywhere
int a = ref.read(myProvider);

// Inside a build method
int a = ref.watch(myProvider);
```

### ➤ FutureProvider

Use this provider for asynchronous values that never change.

Example use cases:
- fetch static data from an API (that does not change)
- fetch device information (that does not change)

The advantage over `FutureBuilder` is that the value is cached and the future is only called once.

```dart
import 'package:package_info_plus/package_info_plus.dart';

final versionProvider = FutureProvider((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});
```

Access:

```dart
build(BuildContext context) {
  AsyncSnapshot<String> versionAsync = ref.watch(versionProvider);
  return versionAsync.when(
    data: (version) => Text('Version: $version'),
    loading: () => const CircularProgressIndicator(),
    error: (error, stackTrace) => Text('Error: $error'),
  );
}
```

### ➤ StateProvider

The `StateProvider` is handy for simple use cases where you only need a `setState` method.

```dart
final myProvider = StateProvider((ref) => 10);
```

Update the state:

```dart
ref.notifier(myProvider).setState((old) => old + 1);
```

### ➤ NotifierProvider

Use this provider for mutable values.

This provider can be used in an MVC-like pattern.

The notifiers are **never** disposed. You may have custom logic to delete values within a state.

```dart
final counterProvider = NotifierProvider<Counter, int>((ref) => Counter());

class Counter extends Notifier<int> {
  @override
  int init() => 10;

  void increment() => state++;
}
```

To access the value:

```dart
// Everywhere
int a = ref.read(counterProvider);

// Inside a build method
int a = ref.watch(counterProvider);
```

To access the notifier:

```dart
Counter counter = ref.notifier(counterProvider);
```

Or within a click handler:

```dart
ElevatedButton(
  onPressed: () {
    ref.notifier(counterProvider).increment();
  },
  child: const Text('+ 1'),
)
```

### ➤ AsyncNotifierProvider

Use this provider for mutable async values.

```dart
final counterProvider = AsyncNotifierProvider<Counter, int>((ref) => Counter());

class Counter extends AsyncNotifier<int> {
  @override
  Future<int> init() async {
    await Future.delayed(const Duration(seconds: 1));
    return 0;
  }

  void increment() async {
    // Set `future` to update the state.
    future = ref.notifier(apiProvider).fetchAsyncNumber();
    
    // Use `setState` to also access the old value.
    setState((snapshot) async => (snapshot.curr ?? 0) + 1);

    // Set `state` directly if you want more control.
    state = AsyncSnapshot.waiting();
    await Future.delayed(const Duration(seconds: 1));
    state = AsyncSnapshot.withData(ConnectionState.done, old + 1);
  }
}
```

Often, you want to implement some kind of refresh logic that shows the previous value while loading.

There is `ref.watchWithPrev` for that.

```dart
final counterState = ref.watchWithPrev(counterProvider);
AsyncSnapshot<int>? prev = counterState.prev; // show the previous value while loading
AsyncSnapshot<int> curr = counterState.curr; // might be AsyncSnapshot.waiting()
```

### ➤ ReduxProvider

The `ReduxProvider` is the strictest option. The `state` is solely altered by events.

This has two main benefits:

- **Logging:** With `RiverpieDebugObserver`, you can see every event in the console.
- **Testing:** You can easily test the state transitions.

It works best with enums or `sealed` classes as an event type:

```dart
sealed class CountEvent {}
class AddEvent extends CountEvent {
  final int addedAmount;
  AddEvent(this.addedAmount);
}
class SubtractEvent extends CountEvent {
  final int subtractedAmount;
  SubtractEvent(this.subtractedAmount);
}
```

In the notifier, the event is handled by `reduce`:

```dart
final counterProvider = ReduxProvider<Counter, int, CountEvent>((ref) {
  return Counter(ref.redux(providerA), ref.redux(providerB));
});

class Counter extends ReduxNotifier<int, CountEvent> {
  final Emittable<ServiceA, EventTypeA> serviceA;
  final Emittable<ServiceB, EventTypeB> serviceB;
  
  Counter(this.serviceA, this.serviceB);
  
  @override
  int init() => 0;

  @override
  int reduce(CountEvent event) {
    return switch (event) {
      AddEvent() => state + event.addedAmount,
      SubtractEvent() => handleSubtract(event, state),
    };
  }

  // Complex logic can be extracted into a separate method.
  // Adding the state parameter makes this easier to test.
  int handleSubtract(CountEvent event, int state) {
    serviceA.emit(SomeEvent());
    serviceB.emit(SomeEvent());
    final stateB = serviceB.state;
    if (stateB == 3) {
      // ...
    }
    return state - event.subtractedAmount;
  }
}
```

The widget can trigger events with `ref.redux(provider).emit(event)`:

```dart
class MyPage extends StatelessWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final state = ref.watch(counterProvider);
    return Scaffold(
      body: Column(
        children: [
          Text(state.toString()),
          ElevatedButton(
            onPressed: () => ref.redux(counterProvider).emit(AddEvent(2)),
            child: const Text('Increment'),
          ),
          ElevatedButton(
            onPressed: () => ref.redux(counterProvider).emit(SubtractEvent(3)),
            child: const Text('Decrement'),
          ),
        ],
      ),
    );
  }
}
```

Don't worry about asynchronous business logic.\
The reduce method is defined as `FutureOr<T> reduce(E event)`.

Here is how the console output could look like:

```text
[Riverpie] Event emitted: [Counter.SubtractEvent] by [MyPage]
[Riverpie] Change by [Counter] triggered by [SubtractEvent]
            - Prev: 5
            - Next: 4
            - Rebuild (1): [MyPage]
```

### ➤ ViewProvider

The `ViewProvider` is the only provider that can `watch` other providers.

This is useful for view models that depend on multiple providers.

This requires more code but makes your app more testable.

```dart
class SettingsVm {
  final String firstName;
  final String lastName;
  final ThemeMode themeMode;
  final void Function() logout;  
}

final settingsVmProvider = ViewProvider((ref) {
  final auth = ref.watch(authProvider);
  final themeMode = ref.watch(themeModeProvider);
  return SettingsVm(
    firstName: auth.firstName,
    lastName: auth.lastName,
    themeMode: themeMode,
    logout: () => ref.notifier(authProvider).logout(),
  );
});
```

The widget:

```dart
class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vm = context.ref.watch(settingsVmProvider);
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            Text('First name: ${vm.firstName}'),
            Text('Last name: ${vm.lastName}'),
            Text('Theme mode: ${vm.themeMode}'),
            ElevatedButton(
              onPressed: vm.logout,
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}
```

## Notifiers

A notifier holds the actual state and triggers rebuilds on widgets listening to them.

Use notifiers in combination with `NotifierProvider`, `AsyncNotifierProvider`, or `ReduxProvider`.

| Provider        | Usage                        | Provider                | Exposes `ref` |
|-----------------|------------------------------|-------------------------|---------------|
| `Notifier`      | For any use case             | `NotifierProvider`      | Yes           |
| `AsyncNotifier` | For async values             | `AsyncNotifierProvider` | Yes           |
| `PureNotifier`  | For clean architectures      | `NotifierProvider`      | No            |
| `ReduxNotifier` | For very clean architectures | `ReduxProvider`         | No            |

### ➤ Notifier

The `Notifier` is the fastest and easiest way to implement a notifier.

It has access to `ref`, so you can access any provider at any time.

```dart
// You need to specify the generics (<..>) to have the correct type inference
// Waiting for https://github.com/dart-lang/language/issues/524
final counterProvider = NotifierProvider<Counter, int>((ref) => Counter());

class Counter extends Notifier<int> {
  @override
  int init() => 10;

  void increment() {
    final anotherValue = ref.read(anotherProvider);
    state++;
  }
}
```

### ➤ PureNotifier

The `PureNotifier` is the stricter option.

It has no access to `ref` making this notifier self-contained.

This is often used in combination with dependency injection, where you provide the dependencies via constructor.

```dart
final counterProvider = NotifierProvider<PureCounter, int>((ref) {
  final persistenceService = ref.read(persistenceProvider);
  return PureCounter(persistenceService);
});

class PureCounter extends PureNotifier<int> {
  final PersistenceService _persistenceService;

  PureCounter(this._persistenceService);
  
  @override
  int init() => 10;

  void increment() {
    counter++;
    _persistenceService.persist();
  }
}
```

### ➤ AsyncNotifier

See [AsyncNotifierProvider](#-asyncnotifierprovider).

### ➤ ReduxNotifier

See [ReduxProvider](#-reduxprovider).

## Using ref

With `ref`, you can access the providers and notifiers.

### ➤ ref.read

Read the value of a provider.

```dart
int a = ref.read(myProvider);
```

### ➤ ref.watch

Read the value of a provider and rebuild the widget when the value changes.

This should be used within a `build` method.

```dart
build(BuildContext context) {
  final currentValue = ref.watch(myProvider);
  
  // ...
}
```

You may add an optional `listener` callback:

```dart
build(BuildContext context) {
  final currentValue = ref.watch(myProvider, listener: (prev, next) {
    print('The value changed from $prev to $next');
  });

  // ...
}
```

### ➤ ref.stream

Similar to `ref.watch` with `listener`, but you need to manage the subscription manually.

The subscription will not be disposed automatically.

Use this outside of a `build` method.

```dart
final subscription = ref.stream(myProvider).listen((value) {
  print('The value changed from ${value.prev} to ${value.next}');
});
```

### ➤ ref.future

Get the `Future` of a `FutureProvider` or an `AsyncNotifierProvider`.

```dart
Future<String> version = ref.future(versionProvider);
```

### ➤ ref.notifier

Get the notifier of a provider.

```dart
Counter counter = ref.notifier(counterProvider);

// or

ref.notifier(counterProvider).increment();
```

### ➤ ref.redux

Emit an event to a `ReduxProvider`.

```dart
ref.redux(myReduxProvider).emit(MyEvent());

await ref.redux(myReduxProvider).emit(MyEvent());
```

## What to choose?

There are lots of providers and notifiers. Which one should you choose?

For most use cases, `Provider` and `Notifier` are more than enough.

If you work in an environment where clean architecture is important,
you may want to use `ReduxProvider` and `ViewProvider`.

Be aware that you will need to write more boilerplate code.

| Providers & Notifiers                       | Boilerplate                    | Testability, Extensibility |
|---------------------------------------------|--------------------------------|----------------------------|
| `Provider`, `StateProvider`                 |                                | Low                        |
| `Provider`, `Notifier`, `PureNotifier`      | notifiers                      | Medium                     |
| `Provider`, `ViewProvider`, `Notifier`      | notifiers, view models         | High                       |
| `Provider`, `ViewProvider`, `ReduxProvider` | notifiers, view models, events | Very high                  |

### ➤ Can I use different providers & notifiers together?

Yes. You can use any combination of providers and notifiers.

The cool thing about notifiers is that they are self-contained.

It is actually pragmatic to use `Notifier` and `ReduxNotifier` together as each of them has its own strengths.

## Performance Optimization

### ➤ Selective watching

You may restrict the rebuilds to only a subset of the state with `provider.select`.

Here, the `==` operator is used to compare the previous and next value.

```dart
build(BuildContext context) {
  final themeMode = ref.watch(
    settingsProvider.select((settings) => settings.themeMode),
  );
  
  // ...
}
```

For more complex logic, you can use `rebuidWhen`.

```dart
build(BuildContext context) {
  final currentValue = ref.watch(
    myProvider,
    rebuildWhen: (prev, next) => prev.attribute != next.attribute,
  );
  
  // ...
}
```

You can use both `select` and `rebuildWhen` at the same time.
The `select` will be applied, when `rebuildWhen` returns `true`.

## ensureRef

In a `StatefulWidget`, you can use `ensureRef` to access the providers and notifiers within `initState`.

You may also use `ref` inside `dispose` because `ref` is guaranteed to be initialized.

Please note that you need `with Riverpie`.

```dart
@override
void initState() {
  super.initState();
  ensureRef((ref) {
    ref.read(myProvider);
  });
  
  // or
  ensureRef();
}

@override
void dispose() {
  ensureRef((ref) {
    // This is safe now because we called `ensureRef` in `initState`
    ref.read(myProvider);
    ref.notifier(myNotifierProvider).doSomething();
  });
  super.dispose();
}
```

## defaultRef

If you are unable to access `ref`, there is a pragmatic solution for that.

You can use `RiverpieScope.defaultRef` to access the providers and notifiers.

Remember that this is only for edge cases, and you should always use the accessible `ref` if possible.

```dart
void someFunction() {
  final ref = RiverpieScope.defaultRef;
  ref.read(myProvider);
  ref.notifier(myNotifierProvider).doSomething();
}
```

## Observer

The `RiverpieScope` accepts an optional `observer`.

You can implement one yourself or just use the included `RiverpieDebugObserver`.

```dart
void main() {
  runApp(
    RiverpieScope(
      observer: kDebugMode ? const RiverpieDebugObserver() : null,
      child: const MyApp(),
    ),
  );
}
```

Now you will see useful information printed into the console:

```text
[Riverpie] Provider initialized: [Counter]
            - Reason: INITIAL ACCESS
            - Value: 10
[Riverpie] Listener added: [SecondPage] on [Counter]
[Riverpie] Change by [Counter]
            - Prev: 10
            - Next: 11
            - Rebuild (2): [HomePage], [SecondPage]
```

In case you want to use multiple observers at once, there is a `RiverpieMultiObserver` for that.

```dart
void main() {
  runApp(
    RiverpieScope(
      observer: RiverpieMultiObserver(
        observers: [
          RiverpieDebugObserver(),
          MyCustomObserver(),
        ],
      ),
      child: const MyApp(),
    ),
  );
}
```

## Testing

### ➤ Override providers

You can override any provider in your tests.

```dart
void main() {
  testWidgets('My test', (tester) async {
    await tester.pumpWidget(
      RiverpieScope(
        overrides: [
          myProvider.overrideWithValue((ref) => 42),
          myNotifierProvider.overrideWithNotifier((ref) => MyNotifier(42)),
        ],
        child: const MyApp(),
      ),
    );
  });
}
```

### ➤ Testing without Flutter

You can use `RiverpieContainer` to test your providers without Flutter.

```dart
void main() {
  test('My test', () {
    final ref = RiverpieContainer();

    expect(ref.read(myCounter), 0);
    ref.notifier(myCounter).increment();
    expect(ref.read(myCounter), 1);
  });
}
```

### ➤ Testing ReduxProvider

For simple tests, you can use `ReduxNotifier.test`.

```dart
void main() {
  test('My test', () {
    final counter = ReduxNotifier.test(
      redux: Counter(),
      initialState: 11,
    );

    expect(counter.state, 11);

    counter.emit(CounterEvent.increment);
    expect(counter.state, 12);

    counter.setState(42); // set state directly
    expect(counter.state, 42);
  });
}
```

To quickly override a `ReduxProvider`, you can use `overrideWithReducer`.

```dart
void main() {
  test('Override test', () {
    final ref = RiverpieContainer(
      overrides: [
        counterProvider.overrideWithReducer(
          overrides: {
            AddEvent: (state, event) => state + 20,
            SubtractEvent: null, // do nothing
          },
        ),
      ],
    );

    expect(ref.read(counterProvider), 0);

    // Should use the overridden reducer
    ref.redux(counterProvider).emit(AddEvent());
    expect(ref.read(counterProvider), 20);

    // Should not change the state
    ref.redux(counterProvider).emit(SubtractEvent());
    expect(ref.read(counterProvider), 20);
  });
}
```

### ➤ Access the state within tests

A `RiverpieScope` is a `Ref`, so you can access the state directly.

```dart
void main() {
  testWidgets('My test', (tester) async {
    final ref = RiverpieScope(
      child: const MyApp(),
    );
    await tester.pumpWidget(ref);

    // ...
    ref.notifier(myNotifier).increment();
    expect(ref.read(myNotifier), 2);
  });
}
```

### ➤ State events

Use `RiverpieHistoryObserver` to keep track of every state change.

```dart
void main() {
  testWidgets('My test', (tester) async {
    final observer = RiverpieHistoryObserver();
    await tester.pumpWidget(
      RiverpieScope(
        observer: observer,
        child: const MyApp(),
      ),
    );

    // ...
    expect(observer.history, [
      ProviderInitEvent(
        provider: myProvider,
        notifier: myNotifier,
        cause: ProviderInitCause.access,
        value: 1,
      ),
      ChangeEvent(
        notifier: myNotifier,
        event: null,
        prev: 1,
        next: 2,
        rebuild: [WidgetRebuildable<MyLoginPage>()],
      ),
    ]);
  });
}
```

### ➤ Example test

There is an example test that shows how to test a counter app.

[See the example test](https://github.com/Tienisto/riverpie/blob/main/documentation/testing.md).

## Dart only

You can use Riverpie without Flutter.

```yaml
# pubspec.yaml
dependencies:
  riverpie: <version>
```

```dart
void main() {
  final ref = RiverpieContainer();
  ref.read(myProvider);
  ref.notifier(myNotifier).doSomething();
  ref.stream(myProvider).listen((value) {
    print('The value changed from ${value.prev} to ${value.next}');
  });
}
```

## License

MIT License

Copyright (c) 2023 Tien Do Nam

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.