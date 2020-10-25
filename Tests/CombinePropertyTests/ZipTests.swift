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

final class ZipTests: XCTestCase {

    func testZip_Unary() {
        let aSubject = PassthroughSubject<Int, Never>()
        let bSubject = PassthroughSubject<Int, Never>()

        let a = Property(initial: 1, then: aSubject)
        let b = Property(initial: 2, then: bSubject)

        let zipped = a.zip(b)

        XCTAssertEqual(zipped.value.0, 1)
        XCTAssertEqual(zipped.value.1, 2)

        aSubject.send(10)

        XCTAssertEqual(zipped.value.0, 1)
        XCTAssertEqual(zipped.value.1, 2)

        bSubject.send(20)

        XCTAssertEqual(zipped.value.0, 10)
        XCTAssertEqual(zipped.value.1, 20)
    }
}
