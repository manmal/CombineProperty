//    MIT License
//
//    Copyright (c) 2020 Manuel Maly
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.

import Combine

/// Represents a property that allows observation of its changes.
/// Heavily inspired by
/// [ReactiveSwift's Property](https://github.com/ReactiveCocoa/ReactiveSwift/blob/master/Sources/Property.swift).
public struct Property<Output> {

    /// The current value.
    public var value: Output { getCurrentValue() }

    /// A publisher sending the current value, and then all subsequent values
    /// as they are received by the `Property`.
    public let allValues: AnyPublisher<Output, Never>

    /// A publisher sending only the subsequent values as they are received by the
    /// `Property` (skipping the current value).
    public let subsequentValues: AnyPublisher<Output, Never>

    private let getCurrentValue: () -> Output

    /// Initializes a Property with an initial value and a publisher of subsequent
    /// values.
    ///
    /// - Parameters:
    ///   - initial: The Property's initial value. Since `then` is immediately subscribed to,
    ///     and `then` can send values synchronously, `self`'s `value` might
    ///     not be equal to `initial` after this initializer returns.
    ///   - then: `Publisher` providing subsequent values for `self`.
    public init<P>(initial: Output, then: P) where P: Publisher, P.Output == Output, P.Failure == Never {
        self.init(unsafePublisher: Just(initial).append(then))
    }

    /// Initializes a Property with a `CurrentValueSubject`.
    /// - Parameters:
    ///   - subject: The `CurrentValueSubject` providing both the current value and all
    ///     subsequent values for the initialized `Property`.
    public init(_ subject: CurrentValueSubject<Output, Never>) {
        self.init(unsafePublisher: subject)
    }

    /// Initializes a Property with a Publisher.
    ///
    /// Heavily inspired by:
    /// https://github.com/ReactiveCocoa/ReactiveSwift/blob/master/Sources/Property.swift#L601
    ///
    /// - Parameters:
    ///   - unsafePublisher: A `Publisher` which has to send at least one value synchronously
    ///     on each subscription.
    internal init<P>(unsafePublisher: P) where P: Publisher, P.Output == Output, P.Failure == Never {
        let currentValue = CurrentValueSubject<Output?, Never>(nil)
        getCurrentValue = { currentValue.value! }
        subsequentValues = {
            let subject = PassthroughSubject<Output, Never>()
            let cancellable = unsafePublisher.sink(
                receiveCompletion: subject.send(completion:),
                receiveValue: { [weak currentValue] value in
                    currentValue?.send(value)
                    subject.send(value)
                }
            )

            return subject
                .extendLifetime(of: cancellable)
                .eraseToAnyPublisher()
        }()

        guard currentValue.value != nil else {
            fatalError("The publisher promised to send at least one value. Received none.")
        }

        allValues = Just(())
            .map { [getCurrentValue] in getCurrentValue() }
            .append(subsequentValues)
            .eraseToAnyPublisher()
    }
}

internal extension Property {

    /// Applies a publisher transformation on `self`, resulting in a `Property` which has
    /// the `transform` applied on all its values.
    ///
    /// - Example for lifting `Publisher.map`, resulting in a mapped `Property<Int>`:
    ///
    ///     `Property(initial: "1", then: Empty()).lift { $0.map { Int($0) } }`
    ///
    /// - Parameters:
    ///   - transform: The closure which will be applied on `self.allValues`. [!] The
    ///   returned `Publisher` must be guaranteed to return a value for every received
    ///   input! For `Publisher` transforms which don't fulfill this requirement, use
    ///   `lift(initial:_:)` instead.
    /// - Returns: A `Property` with all its values (and the current `value`) transformed
    ///   according to `transform`.
    func lift<Q>(_ transform: @escaping (AnyPublisher<Output, Never>) -> Q) -> Property<Q.Output>
    where Q: Publisher, Q.Failure == Never {
        Property<Q.Output>(unsafePublisher: transform(allValues))
    }

    /// Applies a publisher transformation on `self`, resulting in a `Property` which has
    /// the `transform` applied on its subsequent values. The initial value is needed
    /// because the resulting `Property` needs a current value.
    ///
    /// - Example for lifting `Publisher.filter`, resulting in a filtered property:
    ///
    ///     `intProperty.lift(initial: 3) { $0.filter { $0 > 3 } }`
    ///
    /// - Parameters:
    ///   - initial: The initial value
    ///   - transform: The closure which will be applied on `self.subsequentValues`. The
    ///     returned `Publisher` does not need to send a value for each received input.
    /// - Returns: A `Property` with its subsequent values transformed
    ///   according to `transform`.
    func lift<Q>(initial: Q.Output, _ transform: @escaping (AnyPublisher<Output, Never>) -> Q) -> Property<Q.Output>
    where Q: Publisher, Q.Failure == Never {
        Property<Q.Output>(unsafePublisher: Just(initial).append(transform(subsequentValues)))
    }

    /// Applies a transformation on `self` together with a second `Property`. Any
    /// `Publisher` operation combining multiple `Publisher`s (like `combineLatest`)
    /// can be lifted into `Property` this way.
    ///
    /// - Parameters:
    ///   - transform: The closure returning the closure transforming `self`'s `allValues`
    ///     and the other `Property`'s `allValues` into a `Publisher` combining both.
    /// - Returns: A closure which takes a second `Property` and returns the final transformed `Property`.
    func lift<U, Q>(_ transform: @escaping (AnyPublisher<Output, Never>) -> (AnyPublisher<U, Never>) -> Q)
    -> (Property<U>) -> Property<Q.Output>
    where Q: Publisher, Q.Failure == Never {
        return { other in
            Property<Q.Output>(unsafePublisher: transform(allValues)(other.allValues))
        }
    }
}

/// Operators on `Property`. The actual operators are added to the Combine
/// `Publisher`s stored in the `Property`, in order to reuse Combine's own
/// well-tested operators.
///
/// If you are missing an operator (and which cannot be easily replaced by transforming the
/// `Publisher` before it is used to initialize the `Property`), please submit an issue at
/// https://github.com/manmal/combineproperty/issues.
public extension Property {

    /// See `Publisher.map(_:)`
    func map<T>(_ transform: @escaping (Output) -> T) -> Property<T> {
        lift { $0.map(transform) }
    }

    /// See `Publisher.map(_:)`
    func map<T>(_ keyPath: KeyPath<Output, T>) -> Property<T> {
        lift { $0.map(keyPath) }
    }

    /// See `Publisher.map(_:_:)`
    func map<T, U>(_ keyPath0: KeyPath<Output, T>, _ keyPath1: KeyPath<Output, U>) -> Property<(T, U)> {
        lift { $0.map(keyPath0, keyPath1) }
    }

    /// See `Publisher.map(_:_:_:)`
    func map<T, U, V>(
        _ keyPath0: KeyPath<Output, T>,
        _ keyPath1: KeyPath<Output, U>,
        _ keyPath2: KeyPath<Output, V>
    ) -> Property<(T, U, V)> {
        lift { $0.map(keyPath0, keyPath1, keyPath2) }
    }

    /// Replaces all sent values with a certain value.
    /// - Parameters:
    ///   - value: The value to be sent any time `self` sends an upstream value
    func map<T>(value: T) -> Property<T> {
        lift { $0.map { _ in value } }
    }

    /// - Parameters:
    ///   -  initial: The initial value for the resulting `Property`
    ///   -  transform: The closure mapping (and, in case of `nil`, filtering) `self`'s values.
    ///      See `Publisher.compactMap(_:)`.
    func compactMap<T>(initial: T, _ transform: @escaping (Output) -> T?) -> Property<T> {
        lift(initial: initial) { $0.compactMap(transform) }
    }

    /// See `Publisher.zip(_:)`
    func zip<T>(_ other: Property<T>) -> Property<(Output, T)> {
        lift(AnyPublisher.zip(_:))(other)
    }

    /// Filters `self`'s subsequent values.
    /// - Parameters:
    ///   -  initial: The initial value for the resulting `Property`
    ///   -  isIncluded: The closure determining whether a subsequent value shall be sent.
    ///      See `Publisher.filter(_:)`.
    func filter(initial: Output, _ isIncluded: @escaping (Output) -> Bool) -> Property<Output> {
        lift(initial: initial) { $0.filter(isIncluded) }
    }

    /// See `Publisher.flatMap(_:)`
    func flatMap<T>(_ transform: @escaping (Output) -> Property<T>) -> Property<T> {
        lift { $0.flatMap { transform($0).allValues } }
    }

    /// See `Publisher.flatMap(maxPublishers:_:)`. If `maxPublishers` equals .none, then
    /// the demand is corrected to .max(1) to ensure that the resulting `Property`
    /// has a current value.
    func flatMap<T>(
        maxPublishers: Subscribers.Demand = .unlimited,
        _ transform: @escaping (Output) -> Property<T>
    ) -> Property<T> {
        let demand: Subscribers.Demand = maxPublishers == .none ? .max(1) : maxPublishers
        return lift { $0.flatMap(maxPublishers: demand) { transform($0).allValues } }
    }

    /// See `Publisher.removeDuplicates(_:)`
    func removeDuplicates(by predicate: @escaping (Output, Output) -> Bool) -> Property {
        lift { $0.removeDuplicates(by: predicate) }
    }

    /// See `Publisher.combineLatest(_:)`
    func combineLatest<U>(_ other: Property<U>) -> Property<(Output, U)> {
        lift(AnyPublisher.combineLatest)(other)
    }
}

public extension Property where Output == Bool {

    /// Negates all values sent by `self.`
    func negate() -> Property<Bool> {
        lift { $0.map { !$0 } }
    }

    /// Logical AND operation applied on all values sent by `self` and `other`.
    /// - Parameters:
    ///   - other: The `Property` with which `self` is AND-combined.
    func and(_ other: Property<Bool>) -> Property<Bool> {
        combineLatest(other).map { $0 && $1 }
    }

    /// Logical OR operation applied on all values sent by `self` and `other`.
    /// - Parameters:
    ///   - other: The `Property` with which `self` is OR-combined.
    func or(_ other: Property<Bool>) -> Property<Bool> {
        combineLatest(other).map { $0 || $1 }
    }
}

internal extension Publisher {

    /// Extends the lifetime of an object until `self`'s observation is cancelled.
    /// - Parameters:
    ///   - value: The object whose lifetime is extended (retained in ARC).
    func extendLifetime<Retained: AnyObject>(of object: Retained) -> Publishers.Map<Self, Output> {
        map {
            withExtendedLifetime(object, {})
            return $0
        }
    }
}
