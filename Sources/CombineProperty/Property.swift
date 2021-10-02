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
import Foundation

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
    
    
    /// Initializes a Property with a static value.
    /// - Parameters:
    ///   - value: The `Output` value this `Property` will be sending to
    ///     each subscriber.
    public init(_ value: Output) {
        self.init(unsafePublisher: Just(value))
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

// MARK: - Lift

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
        .init(unsafePublisher: transform(allValues))
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
    func lift<Q>(
        initial: Q.Output,
        _ transform: @escaping (AnyPublisher<Output, Never>) -> Q
    ) -> Property<Q.Output>
    where Q: Publisher, Q.Failure == Never {
        .init(unsafePublisher: Just(initial).append(transform(subsequentValues)))
    }

    /// Applies a transformation on `self` together with a second `Property`. Any
    /// `Publisher` operation combining two `Publisher`s (like `combineLatest(_:)`)
    /// can be lifted into `Property` this way.
    ///
    /// - Parameters:
    ///   - transform: The closure returning the closure transforming `self`'s `allValues`
    ///     and the other `Property`'s `allValues` into a `Publisher` combining both.
    /// - Returns: A closure which takes a second `Property` and returns the final
    ///   transformed `Property`.
    func lift<T, P>(
        _ transform: @escaping (AnyPublisher<Output, Never>) -> (AnyPublisher<T, Never>) -> P
    ) -> (Property<T>) -> Property<P.Output>
    where P: Publisher, P.Failure == Never {
        return { other in
            .init(unsafePublisher: transform(allValues)(other.allValues))
        }
    }
}

// MARK: - Catching lift

internal extension Property {

    /// Applies a publisher transformation on `self`, resulting in a `Property` which has
    /// the `transform` applied on all its values, and wrapped into `Result.success`.
    /// Any `Failure` is caught and sent as `Result.failure`.
    ///
    /// - Parameters:
    ///   - transform: The closure which will be applied on `self.allValues`. [!] The
    ///   returned `Publisher` must be guaranteed to return a value for every received
    ///   input! For `Publisher` transforms which don't fulfill this requirement, use
    ///   `lift(initial:_:)` instead.
    /// - Returns: A `Property` with all its values (and the current `value`) transformed
    ///   according to `transform`, and any errors caught.
    func catchingLift<Q>(_ transform: @escaping (AnyPublisher<Output, Never>) -> Q)
    -> Property<Result<Q.Output, Q.Failure>>
    where Q: Publisher {
        let caughtTransform = transform(allValues)
            .map { Result<Q.Output, Q.Failure>.success($0) }
            .catch { Just<Result<Q.Output, Q.Failure>>(Result.failure($0)) }
        return .init(unsafePublisher: caughtTransform)
    }

    /// Applies a publisher transformation on `self`, resulting in a `Property` which has
    /// the `transform` applied on all its values, and wrapped into `Result.success`.
    /// Any `Failure` is caught and sent as `Result.failure`. The initial value is needed
    /// because the resulting `Property` needs a current value.
    ///
    /// - Parameters:
    ///   - initial: The initial value
    ///   - transform: The closure which will be applied on `self.subsequentValues`.
    /// - Returns: A `Property` with its subsequent values transformed
    ///   according to `transform`, and any errors caught.
    func catchingLift<Q>(
        initial: Q.Output,
        _ transform: @escaping (AnyPublisher<Output, Never>) -> Q
    ) -> Property<Result<Q.Output, Q.Failure>>
    where Q: Publisher {
        let caughtTransform = transform(subsequentValues)
            .map { Result<Q.Output, Q.Failure>.success($0) }
            .catch { Just<Result<Q.Output, Q.Failure>>(Result.failure($0)) }
        return .init(unsafePublisher: Just(Result.success(initial)).append(caughtTransform))
    }
}

// MARK: - Standard operators

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
    func map<T, U>(
        _ keyPath0: KeyPath<Output, T>,
        _ keyPath1: KeyPath<Output, U>
    ) -> Property<(T, U)> {
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

    /// Replaces all sent values with a certain value, resulting in a
    /// constant Property.
    /// - Parameters:
    ///   - value: The value to be sent any time `self` sends an upstream value
    func map<T>(value: T) -> Property<T> {
        lift { $0.map { _ in value } }
    }

    /// - Parameters:
    ///   -  initial: The initial value for the resulting `Property`
    ///   -  transform: The closure mapping (and, in case of `nil`, filtering) `self`'s values.
    ///      See `Publisher.compactMap(_:)`.
    func compactMap<T>(initialFallback: T, _ transform: @escaping (Output) -> T?) -> Property<T> {
        lift(initial: transform(value) ?? initialFallback) { $0.compactMap(transform) }
    }

    /// See `Publisher.zip(_:)`
    func zip<T>(_ other: Property<T>) -> Property<(Output, T)> {
        lift(AnyPublisher.zip(_:))(other)
    }

    /// See `Publisher.zip(_:_:)`
    func zip<T, U>(_ p1: Property<T>, _ p2: Property<U>) -> Property<(Output, T, U)> {
        .init(unsafePublisher: allValues.zip(p1.allValues, p2.allValues))
    }

    /// See `Publisher.zip(_:_:)`
    func zip<T, U>(_ other: Property<T>, _ transform: @escaping (Output, T) -> U) -> Property<U> {
        .init(unsafePublisher: allValues.zip(other.allValues, transform))
    }

    /// See `Publisher.zip(_:_:_:)`
    func zip<T, U, V>(
        _ p1: Property<T>,
        _ p2: Property<U>,
        _ transform: @escaping (Output, T, U) -> V
    ) -> Property<V> {
        .init(unsafePublisher: allValues.zip(p1.allValues, p2.allValues, transform))
    }

    /// See `Publisher.zip(_:_:_:)`
    func zip<T, U, V>(
        _ p1: Property<T>,
        _ p2: Property<U>,
        _ p3: Property<V>
    ) -> Property<(Output, T, U, V)> {
        .init(unsafePublisher: allValues.zip(p1.allValues, p2.allValues, p3.allValues))
    }

    /// See `Publisher.zip(_:_:_:_:)`
    func zip<T, U, V, W>(
        _ p1: Property<T>,
        _ p2: Property<U>,
        _ p3: Property<V>,
        _ transform: @escaping (Output, T, U, V) -> W
    )
    -> Property<W> {
        .init(unsafePublisher: allValues.zip(p1.allValues, p2.allValues, p3.allValues, transform))
    }

    /// Filters `self`'s subsequent values.
    /// - Parameters:
    ///   -  initial: The initial value for the resulting `Property`
    ///   -  isIncluded: The closure determining whether a subsequent value shall be sent.
    ///      See `Publisher.filter(_:)`.
    func filter(
        initialFallback: Output,
        _ isIncluded: @escaping (Output) -> Bool
    ) -> Property<Output> {
        lift(initial: isIncluded(value) ? value : initialFallback) { $0.filter(isIncluded) }
    }

    /// Drops `self`'s subsequent values until `predicate` returns `false`.
    /// - Parameters:
    ///   -  initial: The initial value for the resulting `Property`
    ///   -  while: The closure determining whether subsequent values should still be dropped.
    ///      See `Publisher.drop(while:)`.
    func drop(
        initialFallback: Output,
        while predicate: @escaping (Output) -> Bool
    ) -> Property<Output> {
        lift(initial: predicate(value) ? initialFallback : value) { $0.drop(while: predicate) }
    }

    /// Sends `self`'s subsequent values until `predicate` returns `false`.
    /// - Parameters:
    ///   -  initial: The initial value for the resulting `Property`
    ///   -  while: The closure determining whether subsequent values should still be sent.
    ///      See `Publisher.prefix(while:)`.
    func prefix(
        initialFallback: Output,
        while predicate: @escaping (Output) -> Bool
    ) -> Property<Output> {
        lift(initial: predicate(value) ? value: initialFallback) { $0.prefix(while: predicate) }
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
    func combineLatest<T>(_ other: Property<T>) -> Property<(Output, T)> {
        lift(AnyPublisher.combineLatest)(other)
    }

    /// See `Publisher.combineLatest(_:_:)`
    func combineLatest<T, U>(
        _ other: Property<T>,
        _ transform: @escaping (Output, T) -> U
    ) -> Property<U> {
        combineLatest(other)
            .map(transform)
    }

    /// See `Publisher.combineLatest(_:_:)`
    func combineLatest<T, U>(
        _ p1: Property<T>,
        _ p2: Property<U>
    ) -> Property<(Output, T, U)> {
        combineLatest(p1)
            .combineLatest(p2)
            .map { ($0.0.0, $0.0.1, $0.1) }
    }

    /// See `Publisher.combineLatest(_:_:_:)`
    func combineLatest<T, U, V>(
        _ p1: Property<T>,
        _ p2: Property<U>,
        _ transform: @escaping (Output, T, U) -> V
    ) -> Property<V> {
        combineLatest(p1, p2).map(transform)
    }

    /// See `Publisher.combineLatest(_:_:_:)`
    func combineLatest<T, U, V>(
        _ p1: Property<T>,
        _ p2: Property<U>,
        _ p3: Property<V>
    ) -> Property<(Output, T, U, V)> {
        combineLatest(p1)
            .combineLatest(p2)
            .combineLatest(p3)
            .map { ($0.0.0.0, $0.0.0.1, $0.0.1, $0.1) }
    }

    /// See `Publisher.combineLatest(_:_:_:_:)`
    func combineLatest<T, U, V, W>(
        _ p1: Property<T>,
        _ p2: Property<U>,
        _ p3: Property<V>,
        _ transform: @escaping (Output, T, U, V) -> W
    ) -> Property<W> {
        combineLatest(p1, p2, p3).map(transform)
    }

    /// Combines upstream's value with `others`' values, and sends a new Array
    /// whenever one of the Properties sends a new value.
    func combineLatest<Others: Collection>(with others: Others) -> Property<[Output]>
        where Others.Element == Property<Output> {
        let combinedPublisher = self.allValues.combineLatest(with: others.map(\.allValues))
        return .init(unsafePublisher: combinedPublisher)
    }

    /// Combines the provided `properties`' values, and sends a new Array
    /// whenever one of the Properties sends a new value.
    /// - Parameters:
    ///   - properties: Collection of `Property`s which shall be combined.
    ///   - emptySentinel: Fallback value which is used in case `properties` is empty.
    static func combineLatest<Properties: Collection>(
        _ properties: Properties,
        emptySentinel: Output
    ) -> Property<[Output]>
    where Properties.Element == Property<Output> {
        switch properties.count {
        case 0:
            return Property<[Output]>(initial: [emptySentinel], then: Empty())
        case 1:
            return properties[properties.startIndex].map { [$0] }
        default:
            let first = properties[properties.startIndex]
            let others = properties[properties.index(after: properties.startIndex)...]
            return first.combineLatest(with: others)
        }
    }

    /// Decodes the output from the upstream using a specified decoder,
    /// and transforms it to a `Result`.
    /// See `Publisher.decode(type:decoder:)`
    func decode<Item, Coder>(type: Item.Type, decoder: Coder) -> Property<Result<Item, Error>>
    where Coder: TopLevelDecoder, Item: Decodable, Output == Coder.Input {
        catchingLift { $0.decode(type: type, decoder: decoder) }
    }

    /// Specifies the scheduler on which to receive __subsequent__ elements from the Property.
    /// See `Publisher.receive(on:options:)`
    func receive<S>(
        on scheduler: S,
        options: S.SchedulerOptions? = nil
    ) -> Property<Output> where S : Scheduler {
        lift(initial: value) { $0.receive(on: scheduler, options: options) }
    }

    /// See `Publisher.scan(_:_:)`
    func scan<T>(
        _ initialResult: T,
        _ nextPartialResult: @escaping (T, Output) -> T
    ) -> Property<T> {
        lift(initial: initialResult) { $0.scan(initialResult, nextPartialResult) }
    }

    /// Transforms elements from the upstream Property by providing the current element
    /// to a closure along with the last value returned by the closure, reducing both
    /// to a single value.
    /// See `Publisher.scan(_:_:)`
    func scan(_ nextPartialResult: @escaping (Output, Output) -> Output) -> Property {
        scan(value, nextPartialResult)
    }

    /// See `Publisher.switchToLatest()`
    func switchToLatest<T>() -> Property<T> where Output == Property<T> {
        lift { $0.map { $0.allValues }.switchToLatest() }
    }

    /// See `Publisher.replaceNil(with:)`
    func replaceNil<T>(with output: T) -> Property<T> where Output == T? {
        lift { $0.replaceNil(with: output) }
    }

    /// Makes the upstream Property's values optional.
    func optional() -> Property<Output?> {
        map { $0 }
    }
    
    /// Performs nil-coalescing on `self`'s values with `other`'s values.
    ///
    /// - note: As long as `self` is `.some`, `other`'s value will never
    ///         be returned.
    ///
    /// - parameters:
    ///   - other: Publisher providing the fallback value for the nil-coalescing.
    func coalesce<Wrapped>(_ other: Property<Wrapped?>) -> Self where Output == Wrapped? {
        lift { $0.combineLatest(other.allValues).map { $0 ?? $1 }  }
    }

    /// Forwards only those values from `self` that have unique identities across
    /// the set of all values that have been held.
    ///
    /// - note: This causes the identities to be retained to check for
    ///         uniqueness.
    ///
    /// - parameters:
    ///   - transform: A closure that accepts a value and returns identity
    ///                value.
    func uniqueValues<Identity: Hashable>(
        _ transform: @escaping (Output) -> Identity
    ) -> Property {
        let uniqueValues = UniqueValues<Output, Identity>(extract: transform)
        return Property(unsafePublisher: self.allValues.filter(uniqueValues.isUnique))
    }

    /// Forward events from `self` with history: values of the returned property
    /// are a tuple whose first member is the previous value and whose second
    /// member is the current value. `initial` is supplied as the first member
    /// to be be combined with `self`'s current value.
    ///
    /// - parameters:
    ///   - initial: A value that will be combined with `self`'s current value.
    func combinePrevious(_ initial: Output) -> Property<(Output, Output)> {
        let combinePrevious = CombinePrevious(initial: initial)
        let firstTuple = combinePrevious.next(value: value)
        return Property<(Output, Output)>(
            initial: firstTuple,
            then: subsequentValues.map(combinePrevious.next)
        )
    }
}

public extension Property where Output: Equatable {

    /// See `Publisher.removeDuplicates()`
    func removeDuplicates() -> Property {
        lift { $0.removeDuplicates() }
    }
}

public extension Property where Output: Hashable {

    /// Forwards only those values from `self` that are unique across the set of
    /// all values that have been seen.
    ///
    /// - note: This causes the identities to be retained to check for uniqueness.
    ///         Providing a function that returns a unique value for each sent
    ///         value can help you reduce the memory footprint.
    func uniqueValues() -> Property {
        uniqueValues { $0 }
    }
}

private final class UniqueValues<Output, Identity: Hashable> {
    let semaphore = DispatchSemaphore(value: 1)
    let extract: (Output) -> Identity
    var seenIdentities: Set<Identity> = []

    init(extract: @escaping (Output) -> Identity) {
        self.extract = extract
    }

    func isUnique(_ value: Output) -> Bool {
        semaphore.wait()
        defer { semaphore.signal() }
        let identity = extract(value)
        let (inserted, _) = seenIdentities.insert(identity)
        return inserted
    }
}

private final class CombinePrevious<Output> {
    let semaphore = DispatchSemaphore(value: 1)
    var previous: Output

    init(initial: Output) {
        self.previous = initial
    }

    func next(value: Output) -> (Output, Output) {
        semaphore.wait()
        defer { self.previous = value }
        defer { semaphore.signal() }
        return (previous, value)
    }
}

public extension Property where Output: Encodable {

    /// Encodes the output from upstream using a specified encoder,
    /// and transforms it to a `Result`.
    /// See `Publisher.encode(encoder:)`
    func encode<Coder>(encoder: Coder) -> Property<Result<Coder.Output, Error>>
    where Coder : TopLevelEncoder {
        catchingLift { $0.encode(encoder: encoder) }
    }
}

// MARK: - Boolean

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
    
    /// Logical AND operation applied on all of the provided Properties. Sends `true`
    /// whenever all upstream Properties send `true`.
    static func all<Properties: Collection>(_ properties: Properties) -> Property<Bool>
    where Properties.Element == Property<Bool> {
        return Property(
            initial: properties.map { $0.value }.reduce(true) { $0 && $1 },
            then: properties
                .map(\.subsequentValues)
                .combineLatest()
                .map { $0.reduce(true) { $0 && $1 } }
        )
    }

    /// Logical OR operation applied on all of the provided Properties. Sends `true`
    /// whenever any of the upstream Properties send `true`.
    static func any<Properties: Collection>(_ properties: Properties) -> Property<Bool>
    where Properties.Element == Property<Bool> {
        return Property(
            initial: properties.map { $0.value }.reduce(false) { $0 || $1 },
            then: properties
                .map(\.subsequentValues)
                .combineLatest()
                .map { $0.reduce(false) { $0 || $1 } }
        )
    }
}

// MARK: - Publisher Extensions

internal extension Publisher {

    /// Copied from CombineExt:
    /// https://github.com/CombineCommunity/CombineExt/blob/main/Sources/Operators/CombineLatestMany.swift
    func combineLatest<Others: Collection>(with others: Others)
        -> AnyPublisher<[Output], Failure>
        where Others.Element: Publisher,
              Others.Element.Output == Output,
              Others.Element.Failure == Failure {
        let seed = map { [$0] }.eraseToAnyPublisher()

        return others.reduce(seed) { combined, next in
            combined
                .combineLatest(next)
                .map { $0 + [$1] }
                .eraseToAnyPublisher()
        }
    }

    /// Copied from CombineExt:
    /// https://github.com/CombineCommunity/CombineExt/blob/main/Sources/Operators/CombineLatestMany.swift
    func combineLatest<Other: Publisher>(with others: Other...)
        -> AnyPublisher<[Output], Failure>
        where Other.Output == Output, Other.Failure == Failure {
        combineLatest(with: others)
    }

    /// Extends the lifetime of an object until `self`'s observation is cancelled.
    /// - Parameters:
    ///   - object: The object whose lifetime is extended (retained in ARC).
    func extendLifetime<Retained: AnyObject>(of object: Retained) -> Publishers.Map<Self, Output> {
        map {
            withExtendedLifetime(object, {})
            return $0
        }
    }
}

public extension Collection {

    /// Combines `self`'s elements (Properties), sending the resulting array
    /// whenever one of the Properties changes.
    /// - Parameters:
    ///   - emptySentinel: Fallback value which is used in case `self` is empty.
    func combineLatest<Output>(emptySentinel: Output) -> Property<[Output]>
    where Element == Property<Output> {
        Property.combineLatest(self, emptySentinel: emptySentinel)
    }
}

private extension Collection where Element: Publisher {

    /// Copied from CombineExt:
    /// https://github.com/CombineCommunity/CombineExt/blob/main/Sources/Operators/CombineLatestMany.swift
    func combineLatest() -> AnyPublisher<[Element.Output], Element.Failure> {
        switch count {
        case 0:
            return Empty().eraseToAnyPublisher()
        case 1:
            return self[startIndex]
                .combineLatest(with: [Element]())
        default:
            let first = self[startIndex]
            let others = self[index(after: startIndex)...]

            return first
                .combineLatest(with: others)
        }
    }
}
