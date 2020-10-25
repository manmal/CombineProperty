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
import XCTest
@testable import CombineProperty

final class FlatMapTests: XCTestCase {

    func testFlatMap_ReceivesInnerUpdates_Synchronously() {
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
            let cancellable = flatMapped.allValues.sink { value in
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

    func testFlatMap_Retains_MappedPublishers() {

        weak var mappedSubject: PassthroughSubject<Int, Never>?
        var cancellable: AnyCancellable?

        _ = {
            let rootProperty = Property(initial: 0, then: Empty())
            cancellable = rootProperty
                .flatMap { value -> Property<Int> in
                    let passthroughSubject = PassthroughSubject<Int, Never>()
                    mappedSubject = passthroughSubject
                    return Property(initial: 10, then: passthroughSubject)
                }
                .allValues
                .sink { _ in }
        }()

        withExtendedLifetime(cancellable, {
            XCTAssertNotNil(mappedSubject)
        })
    }

    func testFlatMap_Releases_MappedPublishers_OnCancel() {

        weak var mappedSubject: PassthroughSubject<Int, Never>?
        var cancellable: AnyCancellable?

        _ = {
            let rootProperty = Property(initial: 0, then: Empty())
            cancellable = rootProperty
                .flatMap { value -> Property<Int> in
                    let passthroughSubject = PassthroughSubject<Int, Never>()
                    mappedSubject = passthroughSubject
                    return Property(initial: 10, then: passthroughSubject)
                }
                .allValues
                .sink { _ in }
        }()

        cancellable?.cancel()
        cancellable = nil

        XCTAssertNil(mappedSubject)
    }


    func testFlatMap_Completes_OnAllMappedPublishersCompleted() {

        weak var mappedSubject: PassthroughSubject<Int, Never>?
        var cancellable: AnyCancellable?

        let expectation = XCTestExpectation()

        _ = {
            let rootProperty = Property(initial: 0, then: Empty())
            cancellable = rootProperty
                .flatMap { value -> Property<Int> in
                    let passthroughSubject = PassthroughSubject<Int, Never>()
                    mappedSubject = passthroughSubject
                    return Property(initial: 10, then: passthroughSubject)
                }
                .allValues
                .sink(receiveCompletion: { completion in
                    expectation.fulfill()
                }, receiveValue: { _ in })
        }()

        mappedSubject?.send(completion: .finished)

        withExtendedLifetime(cancellable) {
            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 0.1), .completed)
        }
    }

}
