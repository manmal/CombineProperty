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

    /// Initializes a `Property` with the initial value, and a publisher of subsequent
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

    /// Initializes a `Property` with a `CurrentValueSubject`, mirroring its `value`.
    public init(_ subject: CurrentValueSubject<Output, Never>) {
        self.init(unsafePublisher: subject)
    }

    /// Basically a copy of:
    /// https://github.com/ReactiveCocoa/ReactiveSwift/blob/master/Sources/Property.swift#L601
    /// Other approaches were tried, but none were as good as this solution ¯\_(ツ)_/¯
    internal init<P>(unsafePublisher: P) where P: Publisher, P.Output == Output, P.Failure == Never {
        let currentValue = CurrentValueSubject<Output?, Never>(nil)
        getCurrentValue = { currentValue.value! }
        subsequentValues = {
            let subject = PassthroughSubject<Output, Never>()
            let cancellable = unsafePublisher.sink(receiveValue: { [weak currentValue] value in
                currentValue?.send(value)
                subject.send(value)
            })
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
    ///   - transform: The closure which will be applied on `self.allValues`.
    /// - Returns: A `Property` with all its values (and the current `value`) transformed
    ///   according to `transform`.
    func lift<Q>(_ transform: @escaping (AnyPublisher<Output, Never>) -> Q) -> Property<Q.Output>
    where Q: Publisher, Q.Failure == Never {
        Property<Q.Output>(unsafePublisher: transform(allValues))
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

public extension Property {

    func map<T>(_ transform: @escaping (Output) -> T) -> Property<T> {
        lift { $0.map(transform) }
    }

    func flatMap<T>(_ transform: @escaping (Output) -> Property<T>) -> Property<T> {
        lift { $0.flatMap { transform($0).allValues } }
    }

    func removeDuplicates(by predicate: @escaping (Output, Output) -> Bool) -> Property {
        lift { $0.removeDuplicates(by: predicate) }
    }

    func combineLatest<U>(_ other: Property<U>) -> Property<(Output, U)> {
        lift(AnyPublisher.combineLatest)(other)
    }
}

public extension Property where Output == Bool {

    func negate() -> Property<Bool> {
        lift { $0.map { !$0 } }
    }

    func and(_ other: Property<Bool>) -> Property<Bool> {
        combineLatest(other).map { $0 && $1 }
    }

    func or(_ other: Property<Bool>) -> Property<Bool> {
        combineLatest(other).map { $0 || $1 }
    }
}

internal extension Publisher {

    func extendLifetime<Retained>(of value: Retained) -> Publishers.Map<Self, Output> {
        map {
            withExtendedLifetime(value, {})
            return $0
        }
    }
}

public struct DeferredJust<Output>: Publisher {

    public typealias Failure = Never

    let value: () -> Output

    public func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Never {
        subscriber.receive(
            subscription: Sub(subscriber, value: value)
        )
    }

    private class Sub<Downstream: Subscriber>: Subscription where Downstream.Input == Output, Downstream.Failure == Never {

        private var downstream: Downstream?
        private let value: () -> Output

        init(_ downstream: Downstream, value: @escaping () -> Output) {
            self.downstream = downstream
            self.value = value
        }

        func request(_ demand: Subscribers.Demand) {
            guard demand > 0, let downstream = downstream else {
                cancel()
                return
            }
            _ = downstream.receive(value())
            downstream.receive(completion: .finished)
        }

        func cancel() {
            downstream = nil
        }
    }
}
