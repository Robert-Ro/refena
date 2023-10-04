import 'package:meta/meta.dart';
import 'package:refena/src/notifier/base_notifier.dart';
import 'package:refena/src/provider/base_provider.dart';
import 'package:refena/src/provider/override.dart';
import 'package:refena/src/ref.dart';

/// The [ViewProvider] is the only provider that can watch other providers.
/// Its builder is similar to a normal [Provider].
/// A common use case is to define a view model that depends on many providers.
/// Don't worry about the [ref], you can use it freely inside any function.
/// The [ref] will never become invalid.
class ViewProvider<T> extends BaseWatchableProvider<ViewProviderNotifier<T>, T>
    with ProviderSelectMixin<ViewProviderNotifier<T>, T> {
  @internal
  final T Function(WatchableRef ref) builder;

  ViewProvider(this.builder, {String? debugLabel})
      : super(debugLabel: debugLabel ?? 'ViewProvider<$T>');

  @override
  ViewProviderNotifier<T> createState(Ref ref) {
    return ViewProviderNotifier<T>(
      builder,
      debugLabel: customDebugLabel ?? runtimeType.toString(),
    );
  }

  ProviderOverride<ViewProviderNotifier<T>, T> overrideWithBuilder(
    T Function(WatchableRef) builder,
  ) {
    return ProviderOverride(
      provider: this,
      createState: (_) => ViewProviderNotifier(
        builder,
        debugLabel: customDebugLabel ?? runtimeType.toString(),
      ),
    );
  }
}