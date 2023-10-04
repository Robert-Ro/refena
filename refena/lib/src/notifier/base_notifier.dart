import 'dart:async';

import 'package:meta/meta.dart';
import 'package:refena/src/action/redux_action.dart';
import 'package:refena/src/async_value.dart';
import 'package:refena/src/container.dart';
import 'package:refena/src/labeled_reference.dart';
import 'package:refena/src/notifier/listener.dart';
import 'package:refena/src/notifier/notifier_event.dart';
import 'package:refena/src/notifier/rebuildable.dart';
import 'package:refena/src/observer/event.dart';
import 'package:refena/src/observer/observer.dart';
import 'package:refena/src/provider/base_provider.dart';
import 'package:refena/src/provider/override.dart';
import 'package:refena/src/provider/types/redux_provider.dart';
import 'package:refena/src/proxy_ref.dart';
import 'package:refena/src/ref.dart';
import 'package:refena/src/util/batched_stream_controller.dart';
import 'package:refena/src/util/stacktrace.dart';

/// This enum controls the default behaviour of [updateShouldNotify].
/// Keep in mind that you can override [updateShouldNotify] in your notifiers
/// to implement a custom behaviour.
enum NotifyStrategy {
  /// Notify and rebuild whenever we have a new instance.
  /// This is the default behaviour to avoid comparing deeply
  /// nested objects.
  identity,

  /// Notify and rebuild whenever the state in terms of equality (==) changes.
  /// This may result in less rebuilds.
  equality,
}

@internal
abstract class BaseNotifier<T> with LabeledReference {
  bool _initialized = false;
  RefenaContainer? _container;
  RefenaObserver? _observer;
  final String? customDebugLabel;
  BaseProvider? _provider;
  NotifyStrategy? _notifyStrategy;

  /// The current state of the notifier.
  /// It will be initialized by [init].
  late T _state;

  /// A collection of listeners
  final NotifierListeners<T> _listeners = NotifierListeners<T>();

  /// A collection of notifiers that this notifier depends on.
  final Set<BaseNotifier> dependencies = {};

  /// A collection of notifiers that depend on this notifier.
  /// They will be disposed when this notifier is disposed.
  final Set<BaseNotifier> dependents = {};

  BaseNotifier({String? debugLabel}) : customDebugLabel = debugLabel;

  /// The provider that created this notifier.
  /// This is only available after the initialization.
  @nonVirtual
  BaseProvider? get provider => _provider;

  /// Gets the current state.
  @nonVirtual
  T get state => _state;

  /// Sets the state and notify listeners
  @protected
  set state(T value) {
    _setState(value, null);
  }

  /// Sets the state and notify listeners (the actual implementation).
  // We need to extract this method to make [ReduxNotifier] work.
  void _setState(T value, BaseReduxAction? action) {
    if (!_initialized) {
      // We allow initializing the state before the initialization
      // by Refena is done.
      // The only drawback is that ref is not available during this phase.
      // Special providers like [FutureProvider] use this.
      _state = value;
      return;
    }

    final oldState = _state;
    _state = value;

    if (_initialized && updateShouldNotify(oldState, _state)) {
      final observer = _observer;
      if (observer != null) {
        final event = ChangeEvent<T>(
          notifier: this,
          action: action,
          prev: oldState,
          next: value,
          rebuild: [], // will be modified by notifyAll
        );
        _listeners.notifyAll(prev: oldState, next: _state, changeEvent: event);
        observer.handleEvent(event);
      } else {
        _listeners.notifyAll(prev: oldState, next: _state);
      }
    }
  }

  /// This is called on [Ref.dispose].
  /// You can override this method to dispose resources.
  @protected
  @mustCallSuper
  void dispose() {
    _listeners.dispose();

    // Dispose dependents
    for (final dependent in [...dependents]) {
      _container?.dispose(dependent._provider!);
    }

    // Remove from dependency graph
    for (final dependency in dependencies) {
      dependency.dependents.remove(this);
    }
  }

  /// Override this if you want to a different kind of equality.
  @protected
  bool updateShouldNotify(T prev, T next) {
    switch (_notifyStrategy ?? NotifyStrategy.identity) {
      case NotifyStrategy.identity:
        return !identical(prev, next);
      case NotifyStrategy.equality:
        return prev != next;
    }
  }

  @override
  String get debugLabel => customDebugLabel ?? runtimeType.toString();

  /// Override this to provide a custom post initialization.
  /// The initial state is already set at this point.
  void postInit() {}

  /// Handles the actual initialization of the notifier.
  /// Calls [init] internally.
  @internal
  @mustCallSuper
  void internalSetup(
    ProxyRef ref,
    BaseProvider? provider,
  ) {
    _container = ref.container;
    _notifyStrategy = ref.container.defaultNotifyStrategy;
    _provider = provider;
    _observer = ref.container.observer;
  }

  @internal
  List<Rebuildable> getListeners() {
    return _listeners.getListeners();
  }

  @internal
  void cleanupListeners() {
    _listeners.removeUnusedListeners();
  }

  @internal
  void addListener(Rebuildable rebuildable, ListenerConfig<T> config) {
    _listeners.addListener(rebuildable, config);
  }

  @internal
  Stream<NotifierEvent<T>> getStream() {
    return _listeners.getStream();
  }

  @override
  String toString() {
    return '$runtimeType(label: $debugLabel, state: ${_initialized ? _state : 'uninitialized'})';
  }

  /// Subclasses should not override this method.
  /// It is used internally by [dependencies] and [dependents].
  @override
  @nonVirtual
  bool operator ==(Object other) {
    return identical(this, other);
  }

  @override
  @nonVirtual
  int get hashCode => super.hashCode;
}

@internal
abstract class BaseSyncNotifier<T> extends BaseNotifier<T> {
  BaseSyncNotifier({super.debugLabel});

  /// Initializes the state of the notifier.
  /// This method is called only once and
  /// as soon as the notifier is accessed the first time.
  T init();

  @override
  @internal
  @mustCallSuper
  void internalSetup(
    ProxyRef ref,
    BaseProvider? provider,
  ) {
    super.internalSetup(ref, provider);
    _state = init();
    _initialized = true;
  }
}

@internal
abstract class BaseAsyncNotifier<T> extends BaseNotifier<AsyncValue<T>> {
  late Future<T> _future;
  int _futureCount = 0;

  BaseAsyncNotifier({super.debugLabel});

  @protected
  Future<T> get future => _future;

  @protected
  set future(Future<T> value) {
    _setFutureAndListen(value);
  }

  void _setFutureAndListen(Future<T> value) async {
    _future = value;
    _futureCount++;
    state = AsyncValue<T>.loading();
    final currentCount = _futureCount; // after the setter, as it may change
    try {
      final value = await _future;
      if (currentCount != _futureCount) {
        // The future has been changed in the meantime.
        return;
      }
      state = AsyncValue.withData(value);
    } catch (error, stackTrace) {
      if (currentCount != _futureCount) {
        // The future has been changed in the meantime.
        return;
      }
      state = AsyncValue<T>.withError(error, stackTrace);
    }
  }

  @override
  @protected
  set state(AsyncValue<T> value) {
    _futureCount++; // invalidate previous future callbacks
    super.state = value;
  }

  /// Initializes the state of the notifier.
  /// This method is called only once and
  /// as soon as the notifier is accessed the first time.
  Future<T> init();

  @override
  @internal
  @mustCallSuper
  void internalSetup(
    ProxyRef ref,
    BaseProvider? provider,
  ) {
    super.internalSetup(ref, provider);

    // do not set future directly, as the setter may be overridden
    _setFutureAndListen(init());

    _initialized = true;
  }
}

final class ViewProviderNotifier<T> extends BaseSyncNotifier<T>
    implements Rebuildable {
  ViewProviderNotifier(this._builder, {super.debugLabel});

  late final WatchableRef _watchableRef;
  final T Function(WatchableRef) _builder;
  final _rebuildController = BatchedStreamController<AbstractChangeEvent>();
  bool _disposed = false;

  @override
  T init() {
    _rebuildController.stream.listen((event) {
      // rebuild notifier state
      _setStateCustom(
        _build(),
        event,
      );
    });
    return _build();
  }

  T _build() {
    final oldDependencies = {...dependencies};
    dependencies.clear();

    final nextState = _watchableRef.trackNotifier(
      onAccess: (notifier) {
        dependencies.add(notifier);
        notifier.dependents.add(this);
      },
      run: () => _builder(_watchableRef),
    );

    final removedDependencies = oldDependencies.difference(dependencies);
    for (final removedDependency in removedDependencies) {
      removedDependency.dependents.remove(this);
    }

    return nextState;
  }

  // See [BaseNotifier._setState] for reference.
  void _setStateCustom(T value, List<AbstractChangeEvent> causes) {
    if (!_initialized) {
      _state = value;
      return;
    }

    final oldState = _state;
    _state = value;

    if (_initialized && updateShouldNotify(oldState, _state)) {
      final observer = _observer;
      if (observer != null) {
        final event = RebuildEvent<T>(
          rebuildable: this,
          causes: causes,
          prev: oldState,
          next: value,
          rebuild: [], // will be modified by notifyAll
        );
        _listeners.notifyAll(prev: oldState, next: _state, rebuildEvent: event);
        observer.handleEvent(event);
      } else {
        _listeners.notifyAll(prev: oldState, next: _state);
      }
    }
  }

  @internal
  @override
  void internalSetup(
    ProxyRef ref,
    BaseProvider? provider,
  ) {
    _watchableRef = WatchableRef(
      ref: ref.container,
      rebuildable: this,
    );

    super.internalSetup(ref, provider);
  }

  @override
  void rebuild(ChangeEvent? changeEvent, RebuildEvent? rebuildEvent) {
    assert(
      changeEvent == null || rebuildEvent == null,
      'Cannot have both changeEvent and rebuildEvent',
    );

    if (changeEvent != null) {
      _rebuildController.schedule(changeEvent);
    } else if (rebuildEvent != null) {
      _rebuildController.schedule(rebuildEvent);
    } else {
      _rebuildController.schedule(null);
    }
  }

  @override
  @nonVirtual
  void dispose() {
    _disposed = true;
    _rebuildController.dispose();
    super.dispose();
  }

  @override
  bool get disposed => _disposed;

  @override
  bool get isWidget => false;
}

/// A notifier where the state can be updated by dispatching actions
/// by calling [dispatch].
///
/// You do not have access to [Ref] in this notifier, so you need to pass
/// the required dependencies via constructor.
///
/// From outside, you can should dispatch actions with
/// `ref.redux(provider).dispatch(action)`.
///
/// Dispatching from the notifier itself is also possible but
/// you will lose the implicit [debugOrigin] stored in a [Ref].
@internal
abstract class BaseReduxNotifier<T> extends BaseNotifier<T> {
  BaseReduxNotifier({super.debugLabel});

  /// A map of overrides for the reducers.
  Map<Type, MockReducer<T>?>? _overrides;

  /// The override for the initial state.
  T? _overrideInitialState;

  /// Dispatches an action and updates the state.
  /// Returns the new state.
  @internal
  @nonVirtual
  T dispatch(
    SynchronousReduxAction<BaseReduxNotifier<T>, T, dynamic> action, {
    String? debugOrigin,
    LabeledReference? debugOriginRef,
  }) {
    return _dispatchWithResult<dynamic>(
      action,
      debugOrigin: debugOrigin,
      debugOriginRef: debugOriginRef,
    ).$1;
  }

  /// Dispatches an action and updates the state.
  /// Returns the new state along with the result of the action.
  @internal
  @nonVirtual
  (T, R) dispatchWithResult<R>(
    BaseReduxActionWithResult<BaseReduxNotifier<T>, T, R> action, {
    String? debugOrigin,
    LabeledReference? debugOriginRef,
  }) {
    return _dispatchWithResult<R>(
      action,
      debugOrigin: debugOrigin,
      debugOriginRef: debugOriginRef,
    );
  }

  /// Dispatches an action and updates the state.
  /// Returns only the result of the action.
  @internal
  @nonVirtual
  R dispatchTakeResult<R>(
    BaseReduxActionWithResult<BaseReduxNotifier<T>, T, R> action, {
    String? debugOrigin,
    LabeledReference? debugOriginRef,
  }) {
    return _dispatchWithResult<R>(
      action,
      debugOrigin: debugOrigin,
      debugOriginRef: debugOriginRef,
    ).$2;
  }

  @nonVirtual
  (T, R) _dispatchWithResult<R>(
    SynchronousReduxAction<BaseReduxNotifier<T>, T, R> action, {
    required String? debugOrigin,
    required LabeledReference? debugOriginRef,
  }) {
    _observer?.handleEvent(ActionDispatchedEvent(
      debugOrigin: debugOrigin ?? runtimeType.toString(),
      debugOriginRef: debugOriginRef ?? this,
      notifier: this,
      action: action,
    ));

    if (_overrides != null) {
      // Handle overrides
      final key = action.runtimeType;
      final override = _overrides![key];
      if (override != null) {
        // Use the override reducer
        final (T, R) temp = switch (override(state)) {
          T state => (state, null as R),
          (T, R) stateWithResult => stateWithResult,
          _ => throw Exception(
              'Invalid override reducer for ${action.runtimeType}'),
        };
        _setState(temp.$1, action);
        _observer?.handleEvent(ActionFinishedEvent(
          action: action,
          result: temp.$2,
        ));
        return temp;
      } else if (_overrides!.containsKey(key)) {
        // If the override is null (but the key exist),
        // we do not update the state.
        return (state, null as R);
      }
    }

    action.internalSetup(_container, this, _observer);
    try {
      try {
        action.before();
      } catch (error, stackTrace) {
        _observer?.handleEvent(ActionErrorEvent(
          action: action,
          lifecycle: ActionLifecycle.before,
          error: error,
          stackTrace: stackTrace,
        ));
        rethrow;
      }

      try {
        final newState = action.internalWrapReduce();
        _setState(newState.$1, action);
        _observer?.handleEvent(ActionFinishedEvent(
          action: action,
          result: newState.$2,
        ));
        return newState;
      } catch (error, stackTrace) {
        _observer?.handleEvent(ActionErrorEvent(
          action: action,
          lifecycle: ActionLifecycle.reduce,
          error: error,
          stackTrace: stackTrace,
        ));
        rethrow;
      }
    } catch (error) {
      rethrow;
    } finally {
      try {
        action.after();
      } catch (error, stackTrace) {
        _observer?.handleEvent(ActionErrorEvent(
          action: action,
          lifecycle: ActionLifecycle.after,
          error: error,
          stackTrace: stackTrace,
        ));
      }
    }
  }

  /// Dispatches an asynchronous action and updates the state.
  /// Returns the new state.
  @internal
  @nonVirtual
  Future<T> dispatchAsync(
    AsynchronousReduxAction<BaseReduxNotifier<T>, T, dynamic> action, {
    String? debugOrigin,
    LabeledReference? debugOriginRef,
  }) async {
    final (state, _) = await _dispatchAsyncWithResult<dynamic>(
      action,
      debugOrigin: debugOrigin,
      debugOriginRef: debugOriginRef,
    );
    return state;
  }

  /// Dispatches an asynchronous action and updates the state.
  /// Returns the new state along with the result of the action.
  @internal
  @nonVirtual
  Future<(T, R)> dispatchAsyncWithResult<R>(
    BaseAsyncReduxActionWithResult<BaseReduxNotifier<T>, T, R> action, {
    String? debugOrigin,
    LabeledReference? debugOriginRef,
  }) {
    return _dispatchAsyncWithResult<R>(
      action,
      debugOrigin: debugOrigin,
      debugOriginRef: debugOriginRef,
    );
  }

  /// Dispatches an asynchronous action and updates the state.
  /// Returns only the result of the action.
  @internal
  @nonVirtual
  Future<R> dispatchAsyncTakeResult<R>(
    BaseAsyncReduxActionWithResult<BaseReduxNotifier<T>, T, R> action, {
    String? debugOrigin,
    LabeledReference? debugOriginRef,
  }) async {
    final (_, result) = await _dispatchAsyncWithResult<R>(
      action,
      debugOrigin: debugOrigin,
      debugOriginRef: debugOriginRef,
    );
    return result;
  }

  @nonVirtual
  Future<(T, R)> _dispatchAsyncWithResult<R>(
    AsynchronousReduxAction<BaseReduxNotifier<T>, T, R> action, {
    required String? debugOrigin,
    required LabeledReference? debugOriginRef,
  }) async {
    _observer?.handleEvent(ActionDispatchedEvent(
      debugOrigin: debugOrigin ?? runtimeType.toString(),
      debugOriginRef: debugOriginRef ?? this,
      notifier: this,
      action: action,
    ));

    if (_overrides != null) {
      // Handle overrides
      final key = action.runtimeType;
      final override = _overrides![key];
      if (override != null) {
        // Use the override reducer
        final (T, R) temp = switch (override(state)) {
          T state => (state, null as R),
          (T, R) stateWithResult => stateWithResult,
          _ => throw Exception(
              'Invalid override reducer for ${action.runtimeType}'),
        };
        _setState(temp.$1, action);
        _observer?.handleEvent(ActionFinishedEvent(
          action: action,
          result: temp.$2,
        ));
      } else if (_overrides!.containsKey(key)) {
        // If the override is null (but the key exist),
        // we do not update the state.
        return (state, null as R);
      }
    }

    action.internalSetup(_container, this, _observer);

    try {
      try {
        await action.before();
      } catch (error, stackTrace) {
        final extendedStackTrace = extendStackTrace(stackTrace);
        _observer?.handleEvent(ActionErrorEvent(
          action: action,
          lifecycle: ActionLifecycle.before,
          error: error,
          stackTrace: extendedStackTrace,
        ));
        Error.throwWithStackTrace(
          error,
          extendedStackTrace,
        );
      }

      try {
        final newState = await action.internalWrapReduce();
        _setState(newState.$1, action);
        _observer?.handleEvent(ActionFinishedEvent(
          action: action,
          result: newState.$2,
        ));
        return newState;
      } catch (error, stackTrace) {
        final extendedStackTrace = extendStackTrace(stackTrace);
        _observer?.handleEvent(ActionErrorEvent(
          action: action,
          lifecycle: ActionLifecycle.reduce,
          error: error,
          stackTrace: extendedStackTrace,
        ));
        Error.throwWithStackTrace(
          error,
          extendedStackTrace,
        );
      }
    } catch (e) {
      rethrow;
    } finally {
      try {
        action.after();
      } catch (error, stackTrace) {
        _observer?.handleEvent(ActionErrorEvent(
          action: action,
          lifecycle: ActionLifecycle.after,
          error: error,
          stackTrace: stackTrace,
        ));
      }
    }
  }

  @override
  @internal
  set state(T value) {
    throw UnsupportedError('Not allowed to set state directly');
  }

  /// Initializes the state of the notifier.
  /// This method is called only once and
  /// as soon as the notifier is accessed the first time.
  T init();

  /// Override this to provide a custom action that will be
  /// dispatched when the notifier is initialized.
  BaseReduxAction<BaseReduxNotifier<T>, T, dynamic>? get initialAction => null;

  SynchronousReduxAction<BaseReduxNotifier<T>, T, dynamic>? get disposeAction =>
      null;

  @override
  void postInit() {
    switch (initialAction) {
      case SynchronousReduxAction<BaseReduxNotifier<T>, T, dynamic> action:
        dispatch(action);
        break;
      case AsynchronousReduxAction<BaseReduxNotifier<T>, T, dynamic> action:
        dispatchAsync(action);
        break;
      case null:
        break;
      default:
        print(
          'Invalid initialAction type for $debugLabel: ${initialAction.runtimeType}',
        );
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    final disposeAction = this.disposeAction;
    if (disposeAction != null) {
      dispatch(disposeAction);
    }
    super.dispose();
  }

  @override
  @internal
  @mustCallSuper
  void internalSetup(
    ProxyRef ref,
    BaseProvider? provider,
  ) {
    super.internalSetup(ref, provider);
    _state = _overrideInitialState ?? init();
    _initialized = true;
  }
}

/// A wrapper for [BaseSyncNotifier] that exposes [setState] and [state].
/// It creates a container internally, so any ref call still works.
/// This is useful for unit tests.
class TestableNotifier<N extends BaseSyncNotifier<T>, T> {
  TestableNotifier({
    required this.notifier,
    T? initialState,
  }) {
    notifier.internalSetup(
      ProxyRef(
        RefenaContainer(),
        'TestableNotifier',
        LabeledReference.custom('TestableNotifier'),
      ),
      null,
    );
    if (initialState != null) {
      notifier._state = initialState;
    } else {
      notifier._state = notifier.init();
    }
    notifier.postInit();
  }

  /// The wrapped notifier.
  final N notifier;

  /// Updates the state.
  void setState(T state) => notifier._setState(state, null);

  /// Gets the current state.
  T get state => notifier.state;
}

/// A wrapper for [BaseAsyncNotifier] that exposes [setState] and [state].
/// It creates a container internally, so any ref call still works.
/// This is useful for unit tests.
class TestableAsyncNotifier<N extends BaseAsyncNotifier<T>, T> {
  TestableAsyncNotifier({
    required this.notifier,
    AsyncValue<T>? initialState,
  }) {
    notifier.internalSetup(
      ProxyRef(
        RefenaContainer(),
        'TestableAsyncNotifier',
        LabeledReference.custom('TestableAsyncNotifier'),
      ),
      null,
    );
    if (initialState != null) {
      notifier._futureCount++; // invalidate previous future callbacks
      notifier._state = initialState;
    } else {
      notifier._setFutureAndListen(notifier.init());
    }
  }

  /// The wrapped notifier.
  final N notifier;

  /// Updates the state.
  void setState(AsyncValue<T> state) => notifier._setState(state, null);

  /// Sets the future.
  void setFuture(Future<T> future) => notifier._setFutureAndListen(future);

  /// Gets the current state.
  AsyncValue<T> get state => notifier.state;
}

/// A wrapper for [BaseReduxNotifier] that exposes [setState] and [state].
/// This is useful for unit tests.
class TestableReduxNotifier<T> {
  TestableReduxNotifier({
    required this.notifier,
    bool runInitialAction = false,
    T? initialState,
  }) {
    if (initialState != null) {
      notifier._state = initialState;
    } else {
      notifier._state = notifier.init();
    }

    if (runInitialAction) {
      notifier.postInit();
    }
  }

  /// The wrapped notifier.
  final BaseReduxNotifier<T> notifier;

  /// Dispatches an action and updates the state.
  /// Returns the new state.
  T dispatch(
    SynchronousReduxAction<BaseReduxNotifier<T>, T, dynamic> action, {
    String? debugOrigin,
  }) {
    return notifier.dispatch(action, debugOrigin: debugOrigin);
  }

  /// Dispatches an asynchronous action and updates the state.
  /// Returns the new state.
  Future<T> dispatchAsync(
    AsynchronousReduxAction<BaseReduxNotifier<T>, T, dynamic> action, {
    String? debugOrigin,
  }) async {
    return notifier.dispatchAsync(action, debugOrigin: debugOrigin);
  }

  /// Dispatches an action and updates the state.
  /// Returns the new state along with the result of the action.
  (T, R) dispatchWithResult<R>(
    BaseReduxActionWithResult<BaseReduxNotifier<T>, T, R> action, {
    String? debugOrigin,
  }) {
    return notifier.dispatchWithResult(action, debugOrigin: debugOrigin);
  }

  /// Dispatches an action and updates the state.
  /// Returns only the result of the action.
  R dispatchTakeResult<R>(
    BaseReduxActionWithResult<BaseReduxNotifier<T>, T, R> action, {
    String? debugOrigin,
  }) {
    return notifier.dispatchTakeResult(action, debugOrigin: debugOrigin);
  }

  /// Dispatches an asynchronous action and updates the state.
  /// Returns the new state along with the result of the action.
  Future<(T, R)> dispatchAsyncWithResult<R>(
    BaseAsyncReduxActionWithResult<BaseReduxNotifier<T>, T, R> action, {
    String? debugOrigin,
  }) {
    return notifier.dispatchAsyncWithResult(action, debugOrigin: debugOrigin);
  }

  /// Dispatches an asynchronous action and updates the state.
  /// Returns only the result of the action.
  Future<R> dispatchAsyncTakeResult<R>(
    BaseAsyncReduxActionWithResult<BaseReduxNotifier<T>, T, R> action, {
    String? debugOrigin,
  }) {
    return notifier.dispatchAsyncTakeResult(action, debugOrigin: debugOrigin);
  }

  /// Updates the state without dispatching an action.
  void setState(T state) => notifier._setState(state, null);

  /// Gets the current state.
  T get state => notifier.state;
}

typedef MockReducer<T> = Object? Function(T state);

extension ReduxNotifierOverrideExt<N extends BaseReduxNotifier<T>, T,
    E extends Object> on ReduxProvider<N, T> {
  /// Overrides the reducer with the given [overrides].
  ///
  /// Usage:
  /// final ref = RefenaContainer(
  ///   overrides: [
  ///     notifierProvider.overrideWithReducer(
  ///       overrides: {
  ///         MyAction: (state) => state + 1,
  ///         MyAnotherAction: null, // empty reducer
  ///         ...
  ///       },
  ///     ),
  ///   ],
  /// );
  ProviderOverride<N, T> overrideWithReducer({
    N Function(Ref ref)? notifier,
    T? initialState,
    required Map<Type, MockReducer<T>?> overrides,
  }) {
    return ProviderOverride<N, T>(
      provider: this,
      createState: (ref) {
        final createdNotifier = (notifier?.call(ref) ?? createState(ref));
        createdNotifier._overrideInitialState = initialState;
        createdNotifier._overrides = overrides;
        return createdNotifier;
      },
    );
  }

  /// Overrides the initial state with the given [initialState].
  ProviderOverride<N, T> overrideWithInitialState({
    N Function(Ref ref)? notifier,
    required T? initialState,
  }) {
    return ProviderOverride<N, T>(
      provider: this,
      createState: (ref) {
        final createdNotifier = (notifier?.call(ref) ?? createState(ref));
        createdNotifier._overrideInitialState = initialState;
        return createdNotifier;
      },
    );
  }
}