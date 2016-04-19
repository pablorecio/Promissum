//
//  Combinators.swift
//  Promissum
//
//  Created by Tom Lokhorst on 2014-10-11.
//  Copyright (c) 2014 Tom Lokhorst. All rights reserved.
//

import Foundation

/// Flattens a nested Promise of Promise into a single Promise.
///
/// The returned Promise resolves (or rejects) when the nested Promise resolves.
@warn_unused_result(message="Forget to call `then` or `trap`?")
public func flatten<Value, Error>(
  promise: Promise<Promise<Value, Error>, Error>,
  warnUnresolvedDeinit: Warning = .Print,
  file: String = #file,
  line: Int = #line,
  column: Int = #column,
  function: String = #function) -> Promise<Value, Error>
{
  let sourceLocation = SourceLocation(
    file: file,
    line: line,
    column: column,
    function: function)

  let source = PromiseSource<Value, Error>(
    state: .Unresolved,
    dispatch: .Unspecified,
    warnUnresolvedDeinit: warnUnresolvedDeinit,
    callstack: [("flatten", sourceLocation)])

  promise
    .then { p in
      p
        .then(source.resolve)
        .trap(source.reject)
    }
    .trap(source.reject)

  return source.promise
}


/// Creates a Promise that resolves when both arguments resolve.
///
/// The new Promise's value is of a tuple type constructed from both argument promises.
///
/// If either of the two Promises fails, the returned Promise also fails.
@warn_unused_result(message="Forget to call `then` or `trap`?")
public func whenBoth<A, B, Error>(
  promiseA: Promise<A, Error>,
  _ promiseB: Promise<B, Error>,
  warnUnresolvedDeinit: Warning = .Print,
  file: String = #file,
  line: Int = #line,
  column: Int = #column,
  function: String = #function) -> Promise<(A, B), Error>
{
  let sourceLocation = SourceLocation(
    file: file,
    line: line,
    column: column,
    function: function)

  let source = PromiseSource<(A, B), Error>(
    state: .Unresolved,
    dispatch: .Unspecified,
    warnUnresolvedDeinit: warnUnresolvedDeinit,
    callstack: [("whenBoth", sourceLocation)])

  promiseA
    .then { valueA in
      promiseB
        .then { valueB in
          source.resolve((valueA, valueB))
        }
        .trap(source.reject)
    }

  promiseB
    .then { valueB in
      promiseA
        .then { valueA in
          source.resolve((valueA, valueB))
        }
        .trap(source.reject)
    }

  return source.promise
}


/// Creates a Promise that resolves when all of the provided Promises are resolved.
///
/// The new Promise's value is an array of all resolved values.
/// If any of the supplied Promises fails, the returned Promise immediately fails.
///
/// When called with an empty array of promises, this returns a Resolved Promise (with an empty array value).
@warn_unused_result(message="Forget to call `then` or `trap`?")
public func whenAll<Value, Error>(
  promises: [Promise<Value, Error>],
  warnUnresolvedDeinit: Warning = .Print,
  file: String = #file,
  line: Int = #line,
  column: Int = #column,
  function: String = #function) -> Promise<[Value], Error>
{
  let sourceLocation = SourceLocation(
    file: file,
    line: line,
    column: column,
    function: function)

  let source = PromiseSource<[Value], Error>(
    state: .Unresolved,
    dispatch: .Unspecified,
    warnUnresolvedDeinit: warnUnresolvedDeinit,
    callstack: [("whenAll", sourceLocation)])
  var results = promises.map { $0.value }
  var remaining = promises.count

  if remaining == 0 {
    source.resolve([])
  }
  
  for (ix, promise) in promises.enumerate() {

    promise
      .then { value in
        results[ix] = value
        remaining = remaining - 1

        if remaining == 0 {
          source.resolve(results.map { $0! })
        }
      }

    promise
      .trap { error in
        source.reject(error)
      }
    }

  return source.promise
}


/// Creates a Promise that resolves when either argument resolves.
///
/// The new Promise's value is the value of the first promise to resolve.
/// If both argument Promises are already Resolved, the first Promise's value is used.
///
/// If both Promises fail, the returned Promise also fails.
@warn_unused_result(message="Forget to call `then` or `trap`?")
public func whenEither<Value, Error>(
  promise1: Promise<Value, Error>,
  _ promise2: Promise<Value, Error>,
  warnUnresolvedDeinit: Warning = .Print,
  file: String = #file,
  line: Int = #line,
  column: Int = #column,
  function: String = #function) -> Promise<Value, Error>
{
  let sourceLocation = SourceLocation(
    file: file,
    line: line,
    column: column,
    function: function)

  let source = PromiseSource<Value, Error>(
    state: .Unresolved,
    dispatch: .Unspecified,
    warnUnresolvedDeinit: warnUnresolvedDeinit,
    callstack: [("whenAny", sourceLocation)])
  let promises = [promise1, promise2]
  var remaining = promises.count

  for promise in promises {

    promise
      .then { value in
        source.resolve(value)
      }

    promise
      .trap { error in
        remaining = remaining - 1

        if remaining == 0 {
          source.reject(error)
        }
      }
  }

  return source.promise
}

/// Creates a Promise that resolves when any of the argument Promises resolves.
///
/// If all of the supplied Promises fail, the returned Promise fails.
///
/// When called with an empty array of promises, this returns a Promise that will never resolve.
@warn_unused_result(message="Forget to call `then` or `trap`?")
public func whenAny<Value, Error>(
  promises: [Promise<Value, Error>],
  warnUnresolvedDeinit: Warning = .Print,
  file: String = #file,
  line: Int = #line,
  column: Int = #column,
  function: String = #function) -> Promise<Value, Error>
{
  let sourceLocation = SourceLocation(
    file: file,
    line: line,
    column: column,
    function: function)

  let source = PromiseSource<Value, Error>(
    state: .Unresolved,
    dispatch: .Unspecified,
    warnUnresolvedDeinit: warnUnresolvedDeinit,
    callstack: [("whenAny", sourceLocation)])
  var remaining = promises.count

  for promise in promises {

    promise
      .then { value in
        source.resolve(value)
      }

    promise
      .trap { error in
        remaining = remaining - 1

        if remaining == 0 {
          source.reject(error)
        }
      }
  }

  return source.promise
}


/// Creates a Promise that resolves when all provided Promises finalize.
///
/// When called with an empty array of promises, this returns a Resolved Promise.
@warn_unused_result(message="Forget to call `then` or `trap`?")
public func whenAllFinalized<Value, Error>(
  promises: [Promise<Value, Error>],
  warnUnresolvedDeinit: Warning = .Print,
  file: String = #file,
  line: Int = #line,
  column: Int = #column,
  function: String = #function) -> Promise<Void, NoError>
{
  let sourceLocation = SourceLocation(
    file: file,
    line: line,
    column: column,
    function: function)

  let source = PromiseSource<Void, NoError>(
    state: .Unresolved,
    dispatch: .Unspecified,
    warnUnresolvedDeinit: warnUnresolvedDeinit,
    callstack: [("whenAllFinalized", sourceLocation)])
  var remaining = promises.count

  if remaining == 0 {
    source.resolve()
  }

  for promise in promises {

    promise
      .finally {
        remaining = remaining - 1

        if remaining == 0 {
          source.resolve()
        }
      }
  }

  return source.promise
}


/// Creates a Promise that resolves when any of the provided Promises finalize.
///
/// When called with an empty array of promises, this returns a Promise that will never resolve.
@warn_unused_result(message="Forget to call `then` or `trap`?")
public func whenAnyFinalized<Value, Error>(
  promises: [Promise<Value, Error>],
  warnUnresolvedDeinit: Warning = .Print,
  file: String = #file,
  line: Int = #line,
  column: Int = #column,
  function: String = #function) -> Promise<Void, NoError>
{
  let sourceLocation = SourceLocation(
    file: file,
    line: line,
    column: column,
    function: function)

  let source = PromiseSource<Void, NoError>(
    state: .Unresolved,
    dispatch: .Unspecified,
    warnUnresolvedDeinit: warnUnresolvedDeinit,
    callstack: [("whenAnyFinalized", sourceLocation)])

  for promise in promises {

    promise
      .finally {
        source.resolve()
      }
  }

  return source.promise
}

extension Promise {

  /// Returns a Promise where the value information is thrown away.
  @warn_unused_result(message="Forget to call `then` or `trap`?")
  public func mapVoid() -> Promise<Void, Error> {
    return self.map { _ in }
  }

  /// Returns a Promise where the value information is thrown away.
  @available(*, deprecated, renamed="mapVoid")
  @warn_unused_result(message="Forget to call `then` or `trap`?")
  public func void() -> Promise<Void, Error> {
    return self.mapVoid()
  }
}

extension Promise where Error : ErrorType {

  /// Returns a Promise where the error is casted to an ErrorType.
  @warn_unused_result(message="Forget to call `then` or `trap`?")
  public func mapErrorType() -> Promise<Value, ErrorType> {
    return self.mapError { $0 }
  }
}
