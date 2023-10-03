import 'package:refena/refena.dart';
import 'package:test/test.dart';

import '../util/skip_microtasks.dart';

void main() {
  test('Single provider test', () {
    final provider = ViewProvider((ref) => 123);
    final observer = RefenaHistoryObserver.all();
    final ref = RefenaContainer(
      observers: [observer],
    );

    expect(ref.read(provider), 123);

    // Check events
    final notifier = ref.anyNotifier<ViewProviderNotifier<int>, int>(provider);
    expect(observer.history, [
      ProviderInitEvent(
        provider: provider,
        notifier: notifier,
        cause: ProviderInitCause.access,
        value: 123,
      ),
    ]);
  });

  test('Multiple provider test', () async {
    final stateProvider = StateProvider((ref) => 0);
    final viewProvider = ViewProvider((ref) {
      final state = ref.watch(stateProvider);
      return state + 100;
    });
    final observer = RefenaHistoryObserver.all();
    final ref = RefenaContainer(
      observers: [observer],
    );

    expect(ref.read(stateProvider), 0);
    expect(ref.read(viewProvider), 100);

    ref.notifier(stateProvider).setState((old) => old + 1);

    await skipAllMicrotasks();

    expect(ref.read(stateProvider), 1);
    expect(ref.read(viewProvider), 101);

    // Check events
    final stateNotifier = ref.notifier(stateProvider);
    final viewNotifier =
        ref.anyNotifier<ViewProviderNotifier<int>, int>(viewProvider);

    expect(observer.history, [
      ProviderInitEvent(
        provider: stateProvider,
        notifier: stateNotifier,
        cause: ProviderInitCause.access,
        value: 0,
      ),
      ProviderInitEvent(
        provider: viewProvider,
        notifier: viewNotifier,
        cause: ProviderInitCause.access,
        value: 100,
      ),
      ChangeEvent(
        notifier: stateNotifier,
        action: null,
        prev: 0,
        next: 1,
        rebuild: [viewNotifier],
      ),
      RebuildEvent(
        rebuildable: viewNotifier,
        causes: [
          ChangeEvent<int>(
            notifier: stateNotifier,
            action: null,
            prev: 0,
            next: 1,
            rebuild: [viewNotifier],
          ),
        ],
        prev: 100,
        next: 101,
        rebuild: [],
      ),
    ]);
  });

  test('Multiple provider test with provider.select', () async {
    // Providers
    final numberProvider = StateProvider((ref) => 0);
    final stringProvider = StateProvider((ref) => 'a');
    final viewProvider = ViewProvider((ref) {
      final n = ref.watch(numberProvider);
      final s = ref.watch(stringProvider);
      return _ComplexState(n, s);
    });
    final selectiveViewProvider = ViewProvider((ref) {
      return ref.watch(viewProvider.select((state) => state.string));
    });

    final observer = RefenaHistoryObserver.all();
    final ref = RefenaContainer(
      observers: [observer],
    );

    expect(ref.read(viewProvider), _ComplexState(0, 'a'));
    expect(ref.read(selectiveViewProvider), 'a');

    // Update state
    ref.notifier(numberProvider).setState((old) => old + 1);
    await skipAllMicrotasks();

    expect(ref.read(numberProvider), 1);
    expect(ref.read(stringProvider), 'a');
    expect(ref.read(viewProvider), _ComplexState(1, 'a'));
    expect(ref.read(selectiveViewProvider), 'a');

    // Update state
    ref.notifier(stringProvider).setState((old) => '${old}b');
    await skipAllMicrotasks();

    expect(ref.read(numberProvider), 1);
    expect(ref.read(stringProvider), 'ab');
    expect(ref.read(viewProvider), _ComplexState(1, 'ab'));
    expect(ref.read(selectiveViewProvider), 'ab');

    // Check events
    final numberNotifier = ref.notifier(numberProvider);
    final stringNotifier = ref.notifier(stringProvider);
    final viewNotifier =
        ref.anyNotifier<ViewProviderNotifier<_ComplexState>, _ComplexState>(
            viewProvider);
    final selectiveViewNotifier =
        ref.anyNotifier<ViewProviderNotifier<String>, String>(
            selectiveViewProvider);

    expect(observer.history, [
      ProviderInitEvent(
        provider: numberProvider,
        notifier: numberNotifier,
        cause: ProviderInitCause.access,
        value: 0,
      ),
      ProviderInitEvent(
        provider: stringProvider,
        notifier: stringNotifier,
        cause: ProviderInitCause.access,
        value: 'a',
      ),
      ProviderInitEvent(
        provider: viewProvider,
        notifier: viewNotifier,
        cause: ProviderInitCause.access,
        value: _ComplexState(0, 'a'),
      ),
      ProviderInitEvent(
        provider: selectiveViewProvider,
        notifier: selectiveViewNotifier,
        cause: ProviderInitCause.access,
        value: 'a',
      ),
      ChangeEvent(
        notifier: numberNotifier,
        action: null,
        prev: 0,
        next: 1,
        rebuild: [viewNotifier],
      ),
      RebuildEvent(
        rebuildable: viewNotifier,
        causes: [
          ChangeEvent<int>(
            notifier: numberNotifier,
            action: null,
            prev: 0,
            next: 1,
            rebuild: [viewNotifier],
          ),
        ],
        prev: _ComplexState(0, 'a'),
        next: _ComplexState(1, 'a'),
        rebuild: [],
      ),
      ChangeEvent(
        notifier: stringNotifier,
        action: null,
        prev: 'a',
        next: 'ab',
        rebuild: [viewNotifier],
      ),
      RebuildEvent(
        rebuildable: viewNotifier,
        causes: [
          ChangeEvent<String>(
            notifier: stringNotifier,
            action: null,
            prev: 'a',
            next: 'ab',
            rebuild: [viewNotifier],
          ),
        ],
        prev: _ComplexState(1, 'a'),
        next: _ComplexState(1, 'ab'),
        rebuild: [selectiveViewNotifier],
      ),
      RebuildEvent(
        rebuildable: selectiveViewNotifier,
        causes: [
          RebuildEvent<_ComplexState>(
            rebuildable: viewNotifier,
            causes: [
              ChangeEvent<String>(
                notifier: stringNotifier,
                action: null,
                prev: 'a',
                next: 'ab',
                rebuild: [viewNotifier],
              ),
            ],
            prev: _ComplexState(1, 'a'),
            next: _ComplexState(1, 'ab'),
            rebuild: [selectiveViewNotifier],
          ),
        ],
        prev: 'a',
        next: 'ab',
        rebuild: [],
      ),
    ]);
  });
}

class _ComplexState {
  _ComplexState(this.number, this.string);

  final int number;
  final String string;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ComplexState &&
          runtimeType == other.runtimeType &&
          number == other.number &&
          string == other.string;

  @override
  int get hashCode => number.hashCode ^ string.hashCode;

  _ComplexState copyWith({
    int? number,
    String? string,
  }) {
    return _ComplexState(
      number ?? this.number,
      string ?? this.string,
    );
  }
}
