import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:graphql/client.dart';
import 'package:graphql_flutter/src/widgets/hooks/graphql_client.dart';

typedef OnSubscriptionResult<TParsed> = void Function(
  QueryResult<TParsed> subscriptionResult,
  GraphQLClient? client,
);

typedef SubscriptionBuilder<TParsed> = Widget Function(
    QueryResult<TParsed> result);

QueryResult<TParsed> useSubscription<TParsed>(
  SubscriptionOptions<TParsed> options, {
  OnSubscriptionResult<TParsed>? onSubscriptionResult,
}) {
  final client = useGraphQLClient();
  return useSubscriptionOnClient(
    client,
    options,
    onSubscriptionResult: onSubscriptionResult,
  );
}

QueryResult<TParsed> useSubscriptionOnClient<TParsed>(
  GraphQLClient client,
  SubscriptionOptions<TParsed> options, {
  OnSubscriptionResult<TParsed>? onSubscriptionResult,
}) {
  final stream = use(_SubscriptionHook(
    client: client,
    onSubscriptionResult: onSubscriptionResult,
    options: options,
  ));
  final snapshot = useStream(
    stream,
    initialData: options.optimisticResult != null
        ? QueryResult.optimistic(
            data: options.optimisticResult as Map<String, dynamic>?,
            options: options,
          )
        : QueryResult.loading(options: options),
  );
  return snapshot.data!;
}

class _SubscriptionHook<TParsed> extends Hook<Stream<QueryResult<TParsed>>> {
  final SubscriptionOptions<TParsed> options;
  final GraphQLClient client;
  final OnSubscriptionResult<TParsed>? onSubscriptionResult;
  _SubscriptionHook({
    required this.options,
    required this.client,
    required this.onSubscriptionResult,
  });
  @override
  HookState<Stream<QueryResult<TParsed>>, Hook<Stream<QueryResult<TParsed>>>>
      createState() {
    return _SubscriptionHookState();
  }
}

class _SubscriptionHookState<TParsed> extends HookState<
    Stream<QueryResult<TParsed>>, _SubscriptionHook<TParsed>> {
  late Stream<QueryResult<TParsed>> stream;

  bool _isOnline = false;
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;

  void _initSubscription() {
    final client = hook.client;
    stream = client.subscribe(hook.options);
    final onSubscriptionResult = hook.onSubscriptionResult;
    if (onSubscriptionResult != null) {
      stream = stream.map((result) {
        onSubscriptionResult(result, client);
        return result;
      });
    }
  }

  @override
  void initHook() {
    super.initHook();
    _initSubscription();
    _networkSubscription =
        Connectivity().onConnectivityChanged.listen(_onNetworkChange);
  }

  @override
  void didUpdateHook(_SubscriptionHook<TParsed> oldHook) {
    super.didUpdateHook(oldHook);

    if (hook.options != oldHook.options || hook.client != oldHook.client) {
      _initSubscription();
    }
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    super.dispose();
  }

  Future<bool> _isConnected(List<ConnectivityResult> results) async {
    if (results.any((result) => result == ConnectivityResult.none))
      return false;

    final isKnownConnection = !Platform.isAndroid &&
        results.any((result) => [
              ConnectivityResult.mobile,
              ConnectivityResult.ethernet,
              ConnectivityResult.wifi
            ].contains(result));

    if (!isKnownConnection) {
      try {
        final nsLookupResult = await InternetAddress.lookup('google.com');
        if (nsLookupResult.isNotEmpty &&
            nsLookupResult[0].rawAddress.isNotEmpty) {
          return true;
        }
        // on exception -> no real connection, set current state to none
      } on SocketException catch (_) {
        return false;
      }
    }

    return true;
  }

  Future<void> _onNetworkChange(List<ConnectivityResult> results) async {
    final wasOnline = _isOnline;
    _isOnline = await _isConnected(results);

    if (!wasOnline && _isOnline) _initSubscription();
  }

  @override
  Stream<QueryResult<TParsed>> build(BuildContext context) {
    return stream;
  }
}
