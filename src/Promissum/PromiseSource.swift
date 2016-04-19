//
//  PromiseSource.swift
//  Promissum
//
//  Created by Tom Lokhorst on 2014-10-11.
//  Copyright (c) 2014 Tom Lokhorst. All rights reserved.
//

import Foundation

/**
## Creating Promises

A PromiseSource is used to create a Promise that can be resolved or rejected.

Example:

```
let source = PromiseSource<Int, String>()
let promise = source.promise

// Register handlers with Promise
promise
  .then { value in
    print("The value is: \(value)")
  }
  .trap { error in
    print("The error is: \(error)")
  }

// Resolve the source (will call the Promise handler)
source.resolve(42)
```

Once a PromiseSource is Resolved or Rejected it cannot be changed anymore.
All subsequent calls to `resolve` and `reject` are ignored.

## When to use
A PromiseSource is needed when transforming an asynchronous operation into a Promise.

Example:
```
func someOperationPromise() -> Promise<String, ErrorType> {
  let source = PromiseSource<String, ErrorType>()

  someOperation(callback: { (error, value) in
    if let error = error {
      source.reject(error)
    }
    if let value = value {
      source.resolve(value)
    }
  })

  return promise
}
```

## Memory management
Make sure, when creating a PromiseSource, that someone retains a reference to the source.

In the example above the `someOperation` retains the callback.
But in some cases, often when using weak delegates, the callback is not retained.
In that case, you must manually retain the PromiseSource, or the Promise will never complete.

Note that `PromiseSource.deinit` by default will log a warning when an unresolved PromiseSource is deallocated.

*/
public class PromiseSource<Value, Error> {
  typealias ResultHandler = Result<Value, Error> -> Void

  private var handlers: [Result<Value, Error> -> Void] = []

  internal let dispatchMethod: DispatchMethod
  internal let callstack: Callstack

  /// The current state of the PromiseSource
  private(set) public var state: State<Value, Error>

  /// Print a warning on deinit of an unresolved PromiseSource
  public var warnUnresolvedDeinit: Warning

  // MARK: Initializers & deinit

  internal convenience init(value: Value, sourceLocation: SourceLocation)
  {
    let callstack: Callstack = [("PromiseSource", sourceLocation)]

    self.init(
      state: .Resolved(value),
      dispatch: .Unspecified,
      warnUnresolvedDeinit: .DontWarn,
      callstack: callstack)
  }

  internal convenience init(error: Error, sourceLocation: SourceLocation)
  {
    let callstack: Callstack = [("PromiseSource", sourceLocation)]

    self.init(
      state: .Rejected(error),
      dispatch: .Unspecified,
      warnUnresolvedDeinit: .DontWarn,
      callstack: callstack)
  }

  /// Initialize a new Unresolved PromiseSource
  ///
  /// - parameter warnUnresolvedDeinit: Print a warning on deinit of an unresolved PromiseSource
  public convenience init(
    dispatch: DispatchMethod = .Unspecified,
    warnUnresolvedDeinit: Warning = Warning.Print,
    file: String = #file,
    line: Int = #line,
    column: Int = #column,
    function: String = #function)
  {
    let sourceLocation = SourceLocation(
      file: file,
      line: line,
      column: column,
      function: function)

    let callstack: Callstack = [("PromiseSource", sourceLocation)]

    self.init(
      state: .Unresolved,
      dispatch: dispatch,
      warnUnresolvedDeinit: warnUnresolvedDeinit,
      callstack: callstack)
  }

  internal init(
    state: State<Value, Error>,
    dispatch: DispatchMethod,
    warnUnresolvedDeinit: Warning,
    callstack: Callstack)
  {
    self.state = state
    self.dispatchMethod = dispatch
    self.warnUnresolvedDeinit = warnUnresolvedDeinit
    self.callstack = callstack
  }

  deinit {
    guard case .Unresolved = state else { return }
    guard !callstack.isEmpty else { return }

    let message = "Unresolved PromiseSource deallocated, maybe retain this object?\n"
      + "Callstack for deallocated object:\n\(callstackString(callstack))"

    switch warnUnresolvedDeinit {
    case .Print:
      print("WARNING: \(message)")
    case .FatalError:
      fatalError(message)
    case .Callback(let callback):
      callback(callstack)
    case .DontWarn:
      break
    }
  }


  // MARK: Computed properties

  /// Promise related to this PromiseSource
  public var promise: Promise<Value, Error> {
    return Promise(source: self)
  }


  // MARK: Resolve / reject

  /// Resolve an Unresolved PromiseSource with supplied value.
  ///
  /// When called on a PromiseSource that is already Resolved or Rejected, the call is ignored.
  public func resolve(value: Value) {

    resolveResult(.Value(value))
  }


  /// Reject an Unresolved PromiseSource with supplied error.
  ///
  /// When called on a PromiseSource that is already Resolved or Rejected, the call is ignored.
  public func reject(error: Error) {

    resolveResult(.Error(error))
  }

  internal func resolveResult(result: Result<Value, Error>) {

    switch state {
    case .Unresolved:
      state = result.state

      executeResultHandlers(result)
    default:
      break
    }
  }

  private func executeResultHandlers(result: Result<Value, Error>) {

    // Call all previously scheduled handlers
    callHandlers(result, handlers: handlers, dispatchMethod: dispatchMethod)

    // Cleanup
    handlers = []
  }

  // MARK: Adding result handlers

  internal func addOrCallResultHandler(handler: Result<Value, Error> -> Void) {

    switch state {
    case .Unresolved:
      // Save handler for later
      handlers.append(handler)

    case .Resolved(let value):
      // Value is already available, call handler immediately
      callHandlers(Result.Value(value), handlers: [handler], dispatchMethod: dispatchMethod)

    case .Rejected(let error):
      // Error is already available, call handler immediately
      callHandlers(Result.Error(error), handlers: [handler], dispatchMethod: dispatchMethod)
    }
  }
}

internal func callHandlers<T>(value: T, handlers: [T -> Void], dispatchMethod: DispatchMethod) {

  for handler in handlers {
    switch dispatchMethod {
    case .Unspecified:

      if NSThread.isMainThread() {
        handler(value)
      }
      else {
        dispatch_async(dispatch_get_main_queue()) {
          handler(value)
        }
      }

    case .Synchronous:

      handler(value)

    case let .OnQueue(targetQueue):
      let currentQueueLabel = String(UTF8String: dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL))!
      let targetQueueLabel = String(UTF8String: dispatch_queue_get_label(targetQueue))!

      // Assume on correct queue if labels match, but be conservative if label is empty
      let alreadyOnQueue = currentQueueLabel == targetQueueLabel && currentQueueLabel != ""

      if alreadyOnQueue {
        handler(value)
      }
      else {
        dispatch_async(targetQueue) {
          handler(value)
        }
      }
    }
  }
}

public typealias Callstack = [(String, SourceLocation?)]

private func callstackString(callstack: Callstack) -> String {
  var lines: [String] = []

  for (name, location) in callstack {
    if let location = location {
      let name = "\(name):".stringByPaddingToLength(18, withString: " ", startingAtIndex: 0)
      let str = "\(name)\(location.file):\(location.line):\(location.column) - \(location.function)"

      lines.append(str)
    }
    else {

    }
  }

  return lines.joinWithSeparator("\n")
}

public enum Warning {
  case Print
  case FatalError
  case Callback(callstack: Callstack -> ())
  case DontWarn
}

public struct SourceLocation {
  let file: String
  let line: Int
  let column: Int
  let function: String
}
