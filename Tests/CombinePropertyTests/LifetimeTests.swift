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

import Foundation

import Combine
import XCTest
@testable import CombineProperty

final class LifetimeTests: XCTestCase {

    func testAllValuesPublisher_IsNotCancelled_ByPropertyRelease() {

        let passthroughSubject = PassthroughSubject<Int, Never>()
        var cancellable: AnyCancellable?
        var isValueReceived = false

        _ = {
            let property = Property(initial: 0, then: passthroughSubject)
            cancellable = property.subsequentValues.sink { _ in
                isValueReceived = true
            }
        }()

        XCTAssertFalse(isValueReceived)

        passthroughSubject.send(1)

        withExtendedLifetime(cancellable, {
            XCTAssertTrue(isValueReceived)
        })
    }

    func testCurrentValueSubject_IsRetained_ByAllValuesSubscription() {

        weak var weakSubject: CurrentValueSubject<Int, Never>? = nil
        var cancellable: AnyCancellable?

        _ = {
            let subject = CurrentValueSubject<Int, Never>(0)
            let property = Property(subject)
            cancellable = property.allValues.map { String($0) }.sink { _ in }
            weakSubject = subject
        }()

        withExtendedLifetime(cancellable, {
            XCTAssertNotNil(weakSubject)
        })
    }

    func testCurrentValueSubject_IsReleased_AfterCancellationOf_AllValuesSubscription() {

        weak var weakSubject: CurrentValueSubject<Int, Never>? = nil
        var cancellable: AnyCancellable?

        _ = {
            let subject = CurrentValueSubject<Int, Never>(0)
            let property = Property(subject)
            cancellable = property.allValues.map { String($0) }.sink { _ in }
            weakSubject = subject
        }()

        cancellable?.cancel()
        cancellable = nil

        withExtendedLifetime(cancellable, {
            XCTAssertNil(weakSubject)
        })
    }

    func testCurrentValueSubject_IsRetained_BySubsequentValuesSubscription() {

        weak var weakSubject: CurrentValueSubject<Int, Never>? = nil
        var cancellable: AnyCancellable?

        _ = {
            let subject = CurrentValueSubject<Int, Never>(0)
            let property = Property(subject)
            cancellable = property.subsequentValues.map { String($0) }.sink { _ in }
            weakSubject = subject
        }()

        withExtendedLifetime(cancellable, {
            XCTAssertNotNil(weakSubject)
        })
    }

    func testCurrentValueSubject_IsReleased_AfterCancellationOf_SubsequentValuesSubscription() {

        weak var weakSubject: CurrentValueSubject<Int, Never>? = nil
        var cancellable: AnyCancellable?

        _ = {
            let subject = CurrentValueSubject<Int, Never>(0)
            let property = Property(subject)
            cancellable = property.subsequentValues.map { String($0) }.sink { _ in }
            weakSubject = subject
        }()

        cancellable?.cancel()
        cancellable = nil

        withExtendedLifetime(cancellable, {
            XCTAssertNil(weakSubject)
        })
    }

}
