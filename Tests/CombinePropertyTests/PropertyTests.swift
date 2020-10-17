import Combine
import XCTest
@testable import CombineProperty

final class CombinePropertyTests: XCTestCase {
    func testFlatMapReceivesInnerUpdatesSynchronously() {
        let propertyResult: [Int] = {
            let stepsOfTen = (1...2).map { $0 * 10 }

            // Outer values are sent asynchronously
            let root = Property(initial: 0, then: sendInts(stepsOfTen, asyncOn: .main))

            let flatMapped = root.flatMap { stepOfTen -> Property<Int> in
                // Inner values are sent synchronously - they should all be processed during Property.init()
                Property(initial: stepOfTen, then: sendInts(Array(stepOfTen+1...stepOfTen+9)))
            }

            // First inner property should have received 0-9 during .init()
            XCTAssertEqual(flatMapped.value, 9)

            let expectation = XCTestExpectation()
            var receivedValues = [Int]()
            let cancellable = flatMapped.valuesWithCurrent.sink { value in
                receivedValues.append(value)
                if value == 29 {
                    expectation.fulfill()
                }
            }

            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 0.1), .completed)
            _ = cancellable
            return receivedValues
        }()

        let referenceResult = [9, 19, 29]

        XCTAssertEqual(propertyResult, referenceResult)
    }

}

private func sendInt(_ int: Int, asyncOn queue: DispatchQueue? = nil) -> AnyPublisher<Int, Never> {
    let just = Just(int)
    if let queue = queue {
        return just.receive(on: queue).eraseToAnyPublisher()
    } else {
        return just.eraseToAnyPublisher()
    }
}

private func sendInts(_ ints: [Int], asyncOn queue: DispatchQueue? = nil) -> AnyPublisher<Int, Never> {
    guard !ints.isEmpty else { assertionFailure(); return Empty().eraseToAnyPublisher() }

    var publisher = sendInt(ints[0], asyncOn: queue)
    guard ints.count > 1 else { return publisher }
    (1..<ints.count).forEach { publisher = publisher.append(sendInt(ints[$0], asyncOn: queue)).eraseToAnyPublisher() }
    return publisher
}
