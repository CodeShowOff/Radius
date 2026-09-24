import 'package:flutter/material.dart';

/// Result wrapper for async operations with loading/error states.
/// 
/// Use this to handle the three states of async data:
/// - Loading: Operation in progress
/// - Success: Operation completed with data
/// - Error: Operation failed with error
sealed class AsyncResult<T> {
  const AsyncResult();

  /// Create a loading result.
  const factory AsyncResult.loading() = AsyncLoading<T>;

  /// Create a success result with data.
  const factory AsyncResult.success(T data) = AsyncSuccess<T>;

  /// Create an error result.
  const factory AsyncResult.error(String message, {Object? error}) = AsyncError<T>;

  /// Map over the result.
  R when<R>({
    required R Function() loading,
    required R Function(T data) success,
    required R Function(String message, Object? error) error,
  });

  /// Get data or null.
  T? get dataOrNull;

  /// Whether this is loading.
  bool get isLoading;

  /// Whether this is success.
  bool get isSuccess;

  /// Whether this is error.
  bool get isError;
}

final class AsyncLoading<T> extends AsyncResult<T> {
  const AsyncLoading();

  @override
  R when<R>({
    required R Function() loading,
    required R Function(T data) success,
    required R Function(String message, Object? error) error,
  }) => loading();

  @override
  T? get dataOrNull => null;

  @override
  bool get isLoading => true;

  @override
  bool get isSuccess => false;

  @override
  bool get isError => false;
}

final class AsyncSuccess<T> extends AsyncResult<T> {
  final T data;
  const AsyncSuccess(this.data);

  @override
  R when<R>({
    required R Function() loading,
    required R Function(T data) success,
    required R Function(String message, Object? error) error,
  }) => success(data);

  @override
  T? get dataOrNull => data;

  @override
  bool get isLoading => false;

  @override
  bool get isSuccess => true;

  @override
  bool get isError => false;
}

final class AsyncError<T> extends AsyncResult<T> {
  final String message;
  final Object? errorObject;

  const AsyncError(this.message, {Object? error}) : errorObject = error;

  @override
  R when<R>({
    required R Function() loading,
    required R Function(T data) success,
    required R Function(String message, Object? error) error,
  }) => error(message, errorObject);

  @override
  T? get dataOrNull => null;

  @override
  bool get isLoading => false;

  @override
  bool get isSuccess => false;

  @override
  bool get isError => true;
}

/// Widget for displaying async result with standard loading/error/success states.
class AsyncResultBuilder<T> extends StatelessWidget {
  final AsyncResult<T> result;
  final Widget Function(T data) builder;
  final Widget Function()? loadingBuilder;
  final Widget Function(String message, VoidCallback? retry)? errorBuilder;
  final VoidCallback? onRetry;

  const AsyncResultBuilder({
    super.key,
    required this.result,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return result.when(
      loading: () => loadingBuilder?.call() ?? const Center(
        child: CircularProgressIndicator(),
      ),
      success: builder,
      error: (message, _) => errorBuilder?.call(message, onRetry) ?? _DefaultErrorWidget(
        message: message,
        onRetry: onRetry,
      ),
    );
  }
}

class _DefaultErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _DefaultErrorWidget({
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
