import Foundation
import TracerKit
import XCTest

final class OpticsTests: XCTestCase {
    private let up = SIMD3<Float>(0, 1, 0)

    /// A unit direction arriving at the surface, `degrees` from the normal.
    private func incoming(_ degrees: Float) -> SIMD3<Float> {
        let angle = degrees * Float.pi / 180
        return SIMD3<Float>(sin(angle), -cos(angle), 0)
    }

    func testReflectionMirrorsAboutTheNormal() {
        let r = TracerOptics.reflect(incoming(30), normal: up)
        XCTAssertEqual(r.x, sin(Float.pi / 6), accuracy: 1e-6)
        XCTAssertEqual(r.y, cos(Float.pi / 6), accuracy: 1e-6)
        XCTAssertEqual(r.z, 0, accuracy: 1e-6)
    }

    func testRefractionObeysSnellsLaw() throws {
        for degrees in stride(from: Float(0), through: 85, by: 5) {
            for (n1, n2) in [(Float(1), Float(1.5)), (1, 2.42), (1.33, 1)] {
                let incident = incoming(degrees)
                let sinI = sin(degrees * Float.pi / 180)
                guard n1 * sinI <= n2 else { continue }  // beyond the critical angle
                let t = try XCTUnwrap(TracerOptics.refract(incident, normal: up, eta: n1 / n2))
                let length = (t * t).sum().squareRoot()
                XCTAssertEqual(length, 1, accuracy: 1e-5)
                XCTAssertLessThan(t.y, 0, "The transmitted ray continues through the surface")
                XCTAssertEqual(t.z, 0, accuracy: 1e-6, "It stays in the plane of incidence")
                // n₁ sin θ₁ = n₂ sin θ₂
                XCTAssertEqual(n1 * sinI, n2 * t.x, accuracy: 1e-5, "Snell's law at \(degrees)° for \(n1)→\(n2)")
            }
        }
    }

    func testNormalIncidencePassesStraightThrough() throws {
        let t = try XCTUnwrap(TracerOptics.refract(SIMD3<Float>(0, -1, 0), normal: up, eta: 1 / 1.5))
        XCTAssertEqual(t.x, 0, accuracy: 1e-6)
        XCTAssertEqual(t.y, -1, accuracy: 1e-6)
    }

    func testTotalInternalReflectionBeyondTheCriticalAngle() {
        // Glass to air: the critical angle is asin(1 / 1.5), about 41.8°.
        XCTAssertNotNil(TracerOptics.refract(incoming(40), normal: up, eta: 1.5))
        XCTAssertNil(TracerOptics.refract(incoming(43), normal: up, eta: 1.5))
        XCTAssertNil(TracerOptics.refract(incoming(80), normal: up, eta: 1.5))

        let cos43 = cos(Float(43) * Float.pi / 180)
        XCTAssertEqual(TracerOptics.schlickReflectance(cosIncident: cos43, n1: 1.5, n2: 1), 1)
        XCTAssertEqual(TracerOptics.exactReflectance(cosIncident: cos43, n1: 1.5, n2: 1), 1)
        let cos40 = cos(Float(40) * Float.pi / 180)
        XCTAssertLessThan(TracerOptics.schlickReflectance(cosIncident: cos40, n1: 1.5, n2: 1), 1)
    }

    func testFresnelStaysWithinPhysicalBounds() {
        for (n1, n2) in [(Float(1), Float(1.5)), (1.5, 1), (1, 2.42), (2.42, 1), (1.33, 1)] {
            for step in 0...100 {
                let c = Float(step) / 100
                let schlick = TracerOptics.schlickReflectance(cosIncident: c, n1: n1, n2: n2)
                let exact = TracerOptics.exactReflectance(cosIncident: c, n1: n1, n2: n2)
                XCTAssertTrue((0...1).contains(schlick), "Schlick \(schlick) at cos \(c), \(n1)→\(n2)")
                XCTAssertTrue((0...1).contains(exact), "Exact \(exact) at cos \(c), \(n1)→\(n2)")
            }
        }
    }

    func testSchlickTracksTheExactEquationsForEverydayGlassAndWater() {
        // Schlick's approximation is at its worst near grazing incidence, a few
        // percent off for glass and water, and very close elsewhere. It drifts
        // further for diamond-like indices, which the scenes don't use.
        for (n1, n2) in [(Float(1), Float(1.5)), (1.5, 1), (1, 1.33), (1.33, 1)] {
            var worst: Float = 0
            var total: Float = 0
            for step in 0...100 {
                let c = Float(step) / 100
                let schlick = TracerOptics.schlickReflectance(cosIncident: c, n1: n1, n2: n2)
                let exact = TracerOptics.exactReflectance(cosIncident: c, n1: n1, n2: n2)
                worst = max(worst, abs(schlick - exact))
                total += abs(schlick - exact)
            }
            XCTAssertLessThan(worst, 0.065, "Worst-case error for \(n1)→\(n2)")
            XCTAssertLessThan(total / 101, 0.02, "Mean error for \(n1)→\(n2)")
        }
    }

    func testFresnelLimits() {
        // Head-on reflectance is ((n₁ − n₂) / (n₁ + n₂))², 4% for glass.
        XCTAssertEqual(TracerOptics.schlickReflectance(cosIncident: 1, n1: 1, n2: 1.5), 0.04, accuracy: 1e-6)
        XCTAssertEqual(TracerOptics.exactReflectance(cosIncident: 1, n1: 1, n2: 1.5), 0.04, accuracy: 1e-6)
        // Grazing incidence reflects everything.
        XCTAssertEqual(TracerOptics.schlickReflectance(cosIncident: 0, n1: 1, n2: 1.5), 1, accuracy: 1e-6)
        XCTAssertEqual(TracerOptics.exactReflectance(cosIncident: 0, n1: 1, n2: 1.5), 1, accuracy: 1e-6)
        // Index-matched media have no interface to reflect from.
        for c: Float in [0, 0.5, 1] {
            XCTAssertEqual(TracerOptics.exactReflectance(cosIncident: c, n1: 1.2, n2: 1.2), 0)
            XCTAssertEqual(TracerOptics.schlickReflectance(cosIncident: c, n1: 1.2, n2: 1.2), 0)
        }
    }

    func testReflectanceIsReciprocalAcrossTheBoundary() {
        // Light reflects equally whichever way it crosses a boundary. Taking
        // Schlick's cosine on the less dense side preserves that symmetry.
        for degrees in stride(from: Float(0), to: 89, by: 4) {
            let cosI = cos(degrees * Float.pi / 180)
            let sinT = sin(degrees * Float.pi / 180) / 1.5
            let cosT = (1 - sinT * sinT).squareRoot()
            let entering = TracerOptics.schlickReflectance(cosIncident: cosI, n1: 1, n2: 1.5)
            let leaving = TracerOptics.schlickReflectance(cosIncident: cosT, n1: 1.5, n2: 1)
            XCTAssertEqual(entering, leaving, accuracy: 1e-5, "at \(degrees)°")
        }
    }
}
