//
//  PromiseSource.swift
//  Promissum
//
//  Created by Tom Lokhorst on 2014-10-11.
//  Copyright (c) 2014 Tom Lokhorst. All rights reserved.
//

import Foundation

// This Notifier is used to implement Promise.map
internal protocol OriginalSource {
  func registerHandler(handler: () -> Void)
}

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
public class PromiseSource<Value, Error> : OriginalSource {
  typealias ResultHandler = Result<Value, Error> -> Void

  private let originalSource: OriginalSource?
  internal let dispatch: DispatchMethod

  private var handlers: [Result<Value, Error> -> Void] = []

  /// The current state of the PromiseSource
  public var state: State<Value, Error>

  /// Print a warning on deinit of an unresolved PromiseSource
  public var warnUnresolvedDeinit: Bool

  // MARK: Initializers & deinit

  /// Initialize a new Unresolved PromiseSource
  ///
  /// - parameter warnUnresolvedDeinit: Print a warning on deinit of an unresolved PromiseSource
  public convenience init(warnUnresolvedDeinit: Bool = true) {
    self.init(state: .Unresolved, dispatch: .Unspecified, originalSource: nil, warnUnresolvedDeinit: warnUnresolvedDeinit)
  }

  /// Initialize a new Unresolved PromiseSource
  ///
  /// - parameter dispatch: Dispatch method for this PromiseSource
  /// - parameter warnUnresolvedDeinit: Print a warning on deinit of an unresolved PromiseSource
  public convenience init(dispatch: DispatchMethod, warnUnresolvedDeinit: Bool = true) {
    self.init(state: .Unresolved, dispatch: dispatch, originalSource: nil, warnUnresolvedDeinit: warnUnresolvedDeinit)
  }

  internal init(state: State<Value, Error>, dispatch: DispatchMethod, originalSource: OriginalSource?, warnUnresolvedDeinit: Bool) {
    self.state = state
    self.dispatch = dispatch
    self.originalSource = originalSource
    self.warnUnresolvedDeinit = warnUnresolvedDeinit
  }

  deinit {
    if warnUnresolvedDeinit {
      switch state {
      case .Unresolved:
        print("PromiseSource.deinit: WARNING: Unresolved PromiseSource deallocated, maybe retain this object?")
      default:
        break
      }
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
      callHandlers(result, handlers: handlers, dispatch: dispatch)

    // Cleanup
    handlers = []
  }

  // MARK: Adding result handlers

  internal func registerHandler(handler: () -> Void) {
    addOrCallResultHandler({ _ in handler() })
  }

  internal func addOrCallResultHandler(handler: Result<Value, Error> -> Void) {

    switch state {
    case .Unresolved:
      // Register with original source
      // Only call handlers after original completes
      if let originalSource = originalSource {
        originalSource.registerHandler {

          switch self.state {
          case .Resolved(let value):
            // Value is already available, call handler immediately
            callHandlers(Result.Value(value), handlers: [handler], dispatch: self.dispatch)

          case .Rejected(let error):
            // Error is already available, call handler immediately
            callHandlers(Result.Error(error), handlers: [handler], dispatch: self.dispatch)

          case .Unresolved:
            assertionFailure("callback should only be called if state is resolved or rejected")
          }
        }
      }
      else {
        // Save handler for later
        handlers.append(handler)
      }

    case .Resolved(let value):
      // Value is already available, call handler immediately
      callHandlers(Result.Value(value), handlers: [handler], dispatch: dispatch)

    case .Rejected(let error):
      // Error is already available, call handler immediately
      callHandlers(Result.Error(error), handlers: [handler], dispatch: dispatch)
    }
  }
}

internal func callHandlers<T>(arg: T, handlers: [T -> Void], dispatch: DispatchMethod) {

  let queue: dispatch_queue_t?

  // Decide dispatch queue based on provided dispatch method
  switch dispatch {
  case .Unspecified:

    queue = NSThread.isMainThread() ? nil : dispatch_get_main_queue()

  case .Synchronous:
    queue = nil

  case let .OnQueue(targetQueue):
    let currentQueueLabel = String(UTF8String: dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL))!
    let targetQueueLabel = String(UTF8String: dispatch_queue_get_label(targetQueue))!

    // Assume on correct queue if labels match, but be conservative if label is empty
    let alreadyOnQueue = currentQueueLabel == targetQueueLabel && currentQueueLabel != ""

    queue = alreadyOnQueue ? nil : targetQueue
  }

  // Only dispatch async if currect queue isn't correct
  if let queue = queue {
    for handler in handlers {
      dispatch_async(queue) {
        handler(arg)
      }
    }
  }
  else {
    for handler in handlers {
      handler(arg)
    }
  }
}
