import Combine
import Foundation
import XCTest
@testable import CombineProperty

func sendInt(_ int: Int, asyncOn queue: DispatchQueue? = nil) -> AnyPublisher<Int, Never> {
    let just = Just(int)
    if let queue = queue {
        return just.receive(on: queue).eraseToAnyPublisher()
    } else {
        return just.eraseToAnyPublisher()
    }
}

func sendInts(_ ints: [Int], asyncOn queue: DispatchQueue? = nil) -> AnyPublisher<Int, Never> {
    guard !ints.isEmpty else { assertionFailure(); return Empty().eraseToAnyPublisher() }

    var publisher = sendInt(ints[0], asyncOn: queue)
    guard ints.count > 1 else { return publisher }
    (1..<ints.count).forEach { publisher = publisher.append(sendInt(ints[$0], asyncOn: queue)).eraseToAnyPublisher() }
    return publisher
}

final class PropertyBox<Output> {

    let property: Property<Output>

    init(_ property: Property<Output>) {
        self.property = property
    }
}
