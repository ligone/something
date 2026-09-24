import XCTest
@testable import FractalKit

final class ViewportTests: XCTestCase {
    func testCenterMapsToCenter() {
        let viewport = ComplexViewport(centerX: -0.5, centerY: 0.25, scale: 0.01)
        let c = viewport.complex(atX: 400, y: 300, width: 800, height: 600)
        XCTAssertEqual(c.re, -0.5, accuracy: 1e-15)
        XCTAssertEqual(c.im, 0.25, accuracy: 1e-15)
    }

    func testScreenYPointsDownImaginaryAxisPointsUp() {
        let viewport = ComplexViewport(centerX: 0, centerY: 0, scale: 0.01)
        let above = viewport.complex(atX: 400, y: 200, width: 800, height: 600)
        XCTAssertGreaterThan(above.im, 0)
    }

    func testZoomKeepsTheAnchorUnderThePointer() {
        var viewport = ComplexViewport(centerX: -0.75, centerY: 0.1, scale: 0.004)
        let before = viewport.complex(atX: 123, y: 456, width: 800, height: 600)
        viewport.zoom(by: 7.5, aroundX: 123, y: 456, width: 800, height: 600)
        let after = viewport.complex(atX: 123, y: 456, width: 800, height: 600)
        XCTAssertEqual(before.re, after.re, accuracy: 1e-14)
        XCTAssertEqual(before.im, after.im, accuracy: 1e-14)
        XCTAssertEqual(viewport.scale, 0.004 / 7.5, accuracy: 1e-18)
    }

    func testZoomIsClampedToTheSupportedDepth() {
        var viewport = ComplexViewport(centerX: 0, centerY: 0, scale: 1e-12)
        viewport.zoom(by: 1e6, aroundX: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(viewport.scale, ComplexViewport.minimumScale)
    }

    func testPanFollowsTheDrag() {
        var viewport = ComplexViewport(centerX: 0, centerY: 0, scale: 0.01)
        let grabbed = viewport.complex(atX: 300, y: 300, width: 800, height: 600)
        viewport.pan(dx: 50, dy: -20)
        let underPointer = viewport.complex(atX: 350, y: 280, width: 800, height: 600)
        XCTAssertEqual(grabbed.re, underPointer.re, accuracy: 1e-15)
        XCTAssertEqual(grabbed.im, underPointer.im, accuracy: 1e-15)
    }

    func testHomeFramesTheWholeSet() {
        let home = ComplexViewport.home(for: .mandelbrot, width: 1000, height: 700)
        let left = home.complex(atX: 0, y: 350, width: 1000, height: 700)
        let right = home.complex(atX: 1000, y: 350, width: 1000, height: 700)
        let top = home.complex(atX: 500, y: 0, width: 1000, height: 700)
        XCTAssertLessThan(left.re, -2)
        XCTAssertGreaterThan(right.re, 0.47)
        XCTAssertGreaterThan(top.im, 1.12)
    }
}

final class EscapeTimeTests: XCTestCase {
    func testKnownMembers() {
        XCTAssertNil(EscapeTime.mandelbrot(re: 0, im: 0, maxIterations: 1000))
        XCTAssertNil(EscapeTime.mandelbrot(re: -1, im: 0, maxIterations: 1000))
        XCTAssertNil(EscapeTime.mandelbrot(re: -2, im: 0, maxIterations: 1000))
        XCTAssertNil(EscapeTime.mandelbrot(re: -0.1, im: 0.1, maxIterations: 1000))
    }

    func testKnownOutsiders() {
        XCTAssertNotNil(EscapeTime.mandelbrot(re: 1, im: 0, maxIterations: 1000))
        XCTAssertNotNil(EscapeTime.mandelbrot(re: 0.26, im: 0, maxIterations: 1000))
        XCTAssertNotNil(EscapeTime.mandelbrot(re: -2.01, im: 0, maxIterations: 1000))
    }

    func testCardioidShortcutAgreesWithIteration() {
        var checked = 0
        for i in 0..<200 {
            for j in 0..<200 {
                let re = -2 + Double(i) / 200 * 2.6
                let im = -1.3 + Double(j) / 200 * 2.6
                if EscapeTime.isInMainCardioidOrPeriod2Bulb(re: re, im: im) {
                    XCTAssertNil(EscapeTime.smoothCount(zRe: 0, zIm: 0, cRe: re, cIm: im, maxIterations: 5000))
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    func testSmoothCountIsContinuousAcrossBands() {
        // Walk outward along the real axis: integer escape counts jump, but
        // smooth counts should change by far less than one between neighbors.
        var previous: Double?
        var x = 0.26
        while x < 1 {
            let n = EscapeTime.mandelbrot(re: x, im: 0.0001, maxIterations: 10_000)!
            if let previous {
                XCTAssertLessThan(abs(n - previous), 0.9, "Discontinuity near \(x)")
            }
            previous = n
            x += 0.0005
        }
    }

    func testJuliaSetOfZeroIsTheUnitDisk() {
        XCTAssertNil(EscapeTime.julia(re: 0.7, im: 0.7, cRe: 0, cIm: 0, maxIterations: 500))
        XCTAssertNotNil(EscapeTime.julia(re: 0.72, im: 0.72, cRe: 0, cIm: 0, maxIterations: 500))
    }

    func testIterationBudgetGrowsWithDepth() {
        let shallow = EscapeTime.iterationBudget(magnification: 1)
        let deep = EscapeTime.iterationBudget(magnification: 1e9)
        XCTAssertGreaterThan(deep, shallow * 5)
        XCTAssertLessThanOrEqual(EscapeTime.iterationBudget(magnification: 1e30), 12_000)
    }
}

final class DoubleFloatTests: XCTestCase {
    func testSplitCarriesFortyEightBits() {
        let values = [-0.74358611498050853, 0.13197000832336828, 1 / 3.0, .pi, -1.401155189092050]
        for value in values {
            let split = DoubleFloat(value)
            XCTAssertEqual(split.doubleValue, value, accuracy: abs(value) * 1e-14)
            XCTAssertLessThanOrEqual(abs(split.lo), split.hi.ulp)
        }
    }

    func testTwoSumIsErrorFree() {
        let pairs: [(Float, Float)] = [(1, 1e-8), (0.1, 0.2), (-3.75, 1e-12), (123456.7, -0.000321)]
        for (a, b) in pairs {
            let s = DoubleFloat.twoSum(a, b)
            XCTAssertEqual(Double(s.hi) + Double(s.lo), Double(a) + Double(b))
        }
    }

    func testTwoProductIsErrorFree() {
        let pairs: [(Float, Float)] = [(0.1, 0.3), (1.0000001, 0.9999999), (-2.5e-3, 7.1e4)]
        for (a, b) in pairs {
            let p = DoubleFloat.twoProduct(a, b)
            XCTAssertEqual(Double(p.hi) + Double(p.lo), Double(a) * Double(b))
        }
    }

    func testDoubleFloatArithmeticBeatsFloat() {
        let a = 0.7436438870371587
        let b = 0.1318259042053119
        let product = (DoubleFloat(a) * DoubleFloat(b)).doubleValue
        let sum = (DoubleFloat(a) + DoubleFloat(b)).doubleValue
        XCTAssertEqual(product, a * b, accuracy: 1e-14)
        XCTAssertEqual(sum, a + b, accuracy: 1e-14)
        // Plain floats are off by around 1e-8.
        XCTAssertGreaterThan(abs(Double(Float(a) * Float(b)) - a * b), 1e-10)
    }

    func testDoubleFloatIterationTracksDoubleDeepInside() {
        // Twenty Mandelbrot iterations at a deep-zoom coordinate: double-float
        // stays within 1e-9 of the double result while plain float drifts.
        let c = (re: -0.74358611498050853, im: 0.13197000832336828)
        var x = 0.0, y = 0.0
        var dfx = DoubleFloat(0), dfy = DoubleFloat(0)
        let cx = DoubleFloat(c.re), cy = DoubleFloat(c.im)
        for _ in 0..<20 {
            (x, y) = (x * x - y * y + c.re, 2 * x * y + c.im)
            let xx = dfx * dfx
            let yy = dfy * dfy
            let xy = dfx * dfy
            dfx = xx + (-yy) + cx
            dfy = xy + xy + cy
        }
        XCTAssertEqual(dfx.doubleValue, x, accuracy: 1e-9)
        XCTAssertEqual(dfy.doubleValue, y, accuracy: 1e-9)
    }
}

final class PaletteTests: XCTestCase {
    func testLookupTableHasTheRequestedSizeAndIsOpaque() {
        for palette in FractalPalette.all {
            let bytes = palette.rgba8(count: 256)
            XCTAssertEqual(bytes.count, 1024)
            for i in stride(from: 3, to: bytes.count, by: 4) {
                XCTAssertEqual(bytes[i], 255)
            }
        }
    }

    func testPaletteHitsItsStops() {
        let palette = FractalPalette.classic
        for stop in palette.stops {
            let c = palette.color(at: stop.position)
            XCTAssertEqual(c.red, stop.red, accuracy: 0.01)
            XCTAssertEqual(c.green, stop.green, accuracy: 0.01)
            XCTAssertEqual(c.blue, stop.blue, accuracy: 0.01)
        }
    }

    func testPaletteWrapsSeamlessly() {
        for palette in FractalPalette.all {
            let end = palette.color(at: 0.99999)
            let start = palette.color(at: 0)
            XCTAssertEqual(end.red, start.red, accuracy: 0.01, palette.name)
            XCTAssertEqual(end.green, start.green, accuracy: 0.01, palette.name)
            XCTAssertEqual(end.blue, start.blue, accuracy: 0.01, palette.name)
        }
    }

    func testOklabRoundTrip() {
        for (r, g, b) in [(0.2, 0.4, 0.9), (1.0, 1.0, 1.0), (0.0, 0.0, 0.0), (0.9, 0.1, 0.3)] {
            let back = Oklab(red: r, green: g, blue: b).sRGB
            XCTAssertEqual(back.red, r, accuracy: 1e-6)
            XCTAssertEqual(back.green, g, accuracy: 1e-6)
            XCTAssertEqual(back.blue, b, accuracy: 1e-6)
        }
    }
}

final class ZoomFlightTests: XCTestCase {
    let home = ComplexViewport(centerX: -0.74, centerY: 0, scale: 3.1 / 1000)

    func testEndpoints() {
        let target = FractalLandmark.tour[5].viewport(viewWidth: 1000)
        let flight = ZoomFlight(from: home, to: target, viewWidth: 1000)
        XCTAssertEqual(flight.viewport(at: 0), home)
        XCTAssertEqual(flight.viewport(at: 1), target)
        let almost = flight.viewport(at: 0.999999)
        XCTAssertEqual(almost.centerX, target.centerX, accuracy: target.scale * 10)
        XCTAssertEqual(almost.centerY, target.centerY, accuracy: target.scale * 10)
    }

    func testDeepDiveIsSmoothAndMonotonic() {
        let target = FractalLandmark.tour[5].viewport(viewWidth: 1000)
        let flight = ZoomFlight(from: home, to: target, viewWidth: 1000)
        var previous = flight.viewport(at: 0).scale
        for step in 1...400 {
            let scale = flight.viewport(at: Double(step) / 400).scale
            XCTAssertTrue(scale.isFinite && scale > 0)
            XCTAssertLessThanOrEqual(scale, previous * 1.0000001)
            // Constant perceived speed: no frame zooms by more than ~8%.
            XCTAssertGreaterThan(scale / previous, 0.9)
            previous = scale
        }
        XCTAssertGreaterThan(flight.duration, 8)
        XCTAssertLessThan(flight.duration, 40)
    }

    func testTravelBetweenDeepPointsPullsBackOut() {
        let a = FractalLandmark.tour[1].viewport(viewWidth: 1000)
        let b = FractalLandmark.tour[4].viewport(viewWidth: 1000)
        let flight = ZoomFlight(from: a, to: b, viewWidth: 1000)
        let widest = stride(from: 0.0, through: 1.0, by: 0.01).map { flight.viewport(at: $0).scale }.max()!
        XCTAssertGreaterThan(widest, max(a.scale, b.scale) * 1000)
    }

    func testPureZoom() {
        let deeper = ComplexViewport(centerX: home.centerX, centerY: home.centerY, scale: home.scale / 1e6)
        let flight = ZoomFlight(from: home, to: deeper, viewWidth: 1000)
        let middle = flight.viewport(at: 0.5)
        XCTAssertEqual(middle.scale, home.scale / 1e3, accuracy: home.scale / 1e3 * 1e-9)
        XCTAssertEqual(middle.centerX, home.centerX)
    }
}

final class LandmarkTests: XCTestCase {
    func testMinibrotLandmarksAreNuclei() {
        // Each deep landmark sits on a nucleus: iterating its period returns
        // the critical orbit to (almost) exactly zero.
        let nuclei: [(landmark: Int, period: Int)] = [(1, 78), (4, 151), (5, 150)]
        for (index, period) in nuclei {
            let landmark = FractalLandmark.tour[index]
            let refined = MandelbrotNucleus.find(nearRe: landmark.centerX, im: landmark.centerY, period: period)!
            XCTAssertEqual(refined.re, landmark.centerX, accuracy: 1e-15, landmark.name)
            XCTAssertEqual(refined.im, landmark.centerY, accuracy: 1e-15, landmark.name)
            let size = MandelbrotNucleus.size(re: refined.re, im: refined.im, period: period)
            // The framing shows the minibrot with room to spare.
            XCTAssertGreaterThan(landmark.width, size * 5, landmark.name)
            XCTAssertLessThan(landmark.width, size * 40, landmark.name)
        }
    }

    func testAtomDomainPeriodFindsTheMinibrot() {
        let landmark = FractalLandmark.tour[4]
        let nearby = (re: landmark.centerX + 4e-9, im: landmark.centerY - 3e-9)
        XCTAssertEqual(MandelbrotNucleus.atomDomainPeriod(re: nearby.re, im: nearby.im, maxIterations: 5000), 151)
    }

    func testNewtonFindsTheCenterOfThePeriod3Component() {
        // The real period-3 "airplane" component has its nucleus at the real
        // root of c³ + 2c² + c + 1 = 0.
        let nucleus = MandelbrotNucleus.find(nearRe: -1.75, im: 0, period: 3)!
        XCTAssertEqual(nucleus.re, -1.754877666246693, accuracy: 1e-12)
        XCTAssertEqual(nucleus.im, 0, accuracy: 1e-15)
    }

    func testEveryLandmarkShowsBothInsideAndOutside() {
        // A landmark is only interesting if its frame straddles the boundary.
        for landmark in FractalLandmark.tour {
            let viewport = landmark.viewport(viewWidth: 64)
            let home = ComplexViewport.home(for: .mandelbrot, width: 64, height: 40)
            let budget = EscapeTime.iterationBudget(magnification: viewport.magnification(relativeTo: home))
            var escaped = Set<Int>()
            var inside = 0
            for y in 0..<40 {
                for x in 0..<64 {
                    let c = viewport.complex(atX: Double(x), y: Double(y), width: 64, height: 40)
                    if let n = EscapeTime.mandelbrot(re: c.re, im: c.im, maxIterations: budget) {
                        escaped.insert(Int(n))
                    } else {
                        inside += 1
                    }
                }
            }
            XCTAssertGreaterThan(escaped.count, 20, "\(landmark.name) looks flat")
            XCTAssertGreaterThan(inside, 0, "\(landmark.name) never touches the set")
        }
    }
}
