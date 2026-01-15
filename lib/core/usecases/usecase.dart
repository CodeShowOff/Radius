import 'package:dartz/dartz.dart';
import '../error/failures.dart';

/// Base class for use cases with parameters.
/// 
/// Implements a callable interface for cleaner use case invocation.
/// Use [NoParams] for use cases that don't require parameters.
abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

/// Use case parameter class when no parameters are needed.
class NoParams {
  const NoParams();
}
