import Combine

public struct Property<Output> {

    public var value: Output { _value() }
    public let valuesWithCurrent: AnyPublisher<Output, Never>
    public let valuesWithoutCurrent: AnyPublisher<Output, Never>

    private let _value: () -> Output
    private let _valuesWithoutCurrent: PassthroughSubject<Output, Never>
    private let cancellable: AnyCancellable

    /// Initializes a `Property` with the initial value, and a publisher of subsequent
    /// values. The publisher is immediately subscribed to, so the `Property`'s `value`
    /// might not be `initial` when the initializer returns.
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
        let valuesWithoutCurrent = PassthroughSubject<Output, Never>()
        let subject = CurrentValueSubject<Output?, Never>(nil)
        cancellable = unsafePublisher.sink(receiveValue: { [weak subject] value in
            subject?.send(value)
            valuesWithoutCurrent.send(value)
        })
        guard subject.value != nil else {
            fatalError("The publisher promised to send at least one value. Received none.")
        }
        self._value = { subject.value! }
        self.valuesWithCurrent = DeferredJust(value: _value).append(valuesWithoutCurrent).eraseToAnyPublisher()
        self._valuesWithoutCurrent = valuesWithoutCurrent
        self.valuesWithoutCurrent = _valuesWithoutCurrent.retainValue(cancellable).eraseToAnyPublisher()
    }
}

internal extension Property {

    func lift<Q>(_ transform: @escaping (AnyPublisher<Output, Never>) -> Q) -> Property<Q.Output>
    where Q: Publisher, Q.Failure == Never {
        Property<Q.Output>(unsafePublisher: transform(valuesWithCurrent))
    }

    func lift<U, Q>(_ transform: @escaping (AnyPublisher<Output, Never>) -> (AnyPublisher<U, Never>) -> Q)
    -> (Property<U>) -> Property<Q.Output>
    where Q: Publisher, Q.Failure == Never {
        return { other in
            Property<Q.Output>(unsafePublisher: transform(valuesWithCurrent)(other.valuesWithCurrent))
        }
    }
}

public extension Property {

    func map<T>(_ transform: @escaping (Output) -> T) -> Property<T> {
        lift { $0.map(transform) }
    }

    func flatMap<T>(_ transform: @escaping (Output) -> Property<T>) -> Property<T> {
        lift { $0.flatMap { transform($0).valuesWithCurrent } }
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

    func retainValue<Retained>(_ value: Retained) -> Publishers.Map<Self, Output> {
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
