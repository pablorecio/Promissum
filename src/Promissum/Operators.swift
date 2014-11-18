//
//  Operators.swift
//  Promissum
//
//  Created by Tom Lokhorst on 2014-11-18.
//  Copyright (c) 2014 Tom Lokhorst. All rights reserved.
//

import Foundation

infix operator || {
  associativity left
  precedence 110
}

infix operator && {
  associativity left
  precedence 120
}

public func || <T>(lhs: Promise<T>, rhs: Promise<T>) -> Promise<T> {
  return whenEither(lhs, rhs)
}

public func && <A, B>(lhs: Promise<A>, rhs: Promise<B>) -> Promise<(A, B)> {
  return whenBoth(lhs, rhs)
}
