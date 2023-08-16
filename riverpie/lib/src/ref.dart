import 'dart:async';

import 'package:riverpie/src/async_value.dart';
import 'package:riverpie/src/container.dart';
import 'package:riverpie/src/notifier/base_notifier.dart';
import 'package:riverpie/src/notifier/listener.dart';
import 'package:riverpie/src/notifier/notifier_event.dart';
import 'package:riverpie/src/notifier/rebuildable.dart';
import 'package:riverpie/src/notifier/types/async_notifier.dart';
import 'package:riverpie/src/notifier/types/immutable_notifier.dart';
import 'package:riverpie/src/provider/base_provider.dart';
import 'package:riverpie/src/provider/types/async_notifier_provider.dart';

/// The base ref to read and notify providers.
/// These methods can be called anywhere.
/// Even within dispose methods.
/// The primary difficulty is to get the [Ref] in the first place.
abstract class Ref {
  /// Get the current value of a provider without listening to changes.
  T read<N extends BaseNotifier<T>, T>(BaseProvider<N, T> provider);

  /// Get the notifier of a provider.
  N notifier<N extends BaseNotifier<T>, T>(NotifyableProvider<N, T> provider);

  /// Listen for changes to a provider.
  ///
  /// Do not call this method during build as you
  /// will create a new listener every time.
  ///
  /// You need to dispose the subscription manually.
  Stream<NotifierEvent<T>> stream<N extends BaseNotifier<T>, T>(
    BaseProvider<N, T> provider,
  );

  /// Get the [Future] of an [AsyncNotifierProvider].
  Future<T> future<N extends AsyncNotifier<T>, T>(
    AsyncNotifierProvider<N, T> provider,
  );
}

/// The ref available in a [State] with the mixin or in a [ViewProvider].
class WatchableRef extends Ref {
  final RiverpieContainer _ref;
  final Rebuildable _rebuildable;

  @override
  T read<N extends BaseNotifier<T>, T>(BaseProvider<N, T> provider) {
    return _ref.read<N, T>(provider);
  }

  @override
  N notifier<N extends BaseNotifier<T>, T>(NotifyableProvider<N, T> provider) {
    return _ref.notifier<N, T>(provider);
  }

  @override
  Stream<NotifierEvent<T>> stream<N extends BaseNotifier<T>, T>(
    BaseProvider<N, T> provider,
  ) {
    return _ref.stream<N, T>(provider);
  }

  @override
  Future<T> future<N extends AsyncNotifier<T>, T>(
    AsyncNotifierProvider<N, T> provider,
  ) {
    return _ref.future<N, T>(provider);
  }

  /// Get the current value of a provider and listen to changes.
  /// The listener will be disposed automatically when the widget is disposed.
  /// Only call [watch] during build.
  T watch<N extends BaseNotifier<T>, T>(
    BaseProvider<N, T> provider, {
    ListenerCallback<T>? listener,
    bool Function(T prev, T next)? rebuildWhen,
  }) {
    final notifier = _ref.anyNotifier(provider);
    if (notifier is! ImmutableNotifier) {
      notifier.addListener(
        _rebuildable,
        ListenerConfig(
          callback: listener,
          selector: rebuildWhen,
        ),
      );
    }

    // ignore: invalid_use_of_protected_member
    return notifier.state;
  }

  /// Similar to [watch] but also returns the previous value.
  /// Only works with [AsyncNotifierProvider].
  ChronicleSnapshot<T> watchWithPrev<N extends AsyncNotifier<T>, T>(
    AsyncNotifierProvider<N, T> provider, {
    ListenerCallback<AsyncValue<T>>? listener,
    bool Function(AsyncValue<T> prev, AsyncValue<T> next)? rebuildWhen,
  }) {
    final notifier = _ref.anyNotifier(provider);
    notifier.addListener(
      _rebuildable,
      ListenerConfig(
        callback: listener,
        selector: rebuildWhen,
      ),
    );

    // ignore: invalid_use_of_protected_member
    return ChronicleSnapshot(notifier.prev, notifier.state);
  }

  WatchableRef({
    required RiverpieContainer ref,
    required Rebuildable rebuildable,
  })  : _ref = ref,
        _rebuildable = rebuildable;
}

class ChronicleSnapshot<T> {
  /// The state of the notifier before the latest [future] was set.
  /// This is null if [AsyncNotifier.savePrev] is false
  /// or the future has never changed.
  final AsyncValue<T>? prev;

  /// The current state of the notifier.
  final AsyncValue<T> curr;

  ChronicleSnapshot(this.prev, this.curr);
}
