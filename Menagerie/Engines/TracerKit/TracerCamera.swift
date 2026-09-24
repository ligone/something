import Foundation

/// A thin-lens camera.
///
/// With `aperture == 0` it is a pinhole and everything is sharp. Otherwise rays
/// start from random points on a lens disk of diameter `aperture` and converge
/// on the plane `focusDistance` units in front of the camera, perpendicular
/// to the view direction.
public struct TracerCamera: Sendable, Equatable {
    public var position: SIMD3<Float>
    public var target: SIMD3<Float>
    public var up: SIMD3<Float>
    /// Vertical field of view in degrees.
    public var verticalFieldOfView: Float
    /// Lens diameter in world units. 0 gives a pinhole camera.
    public var aperture: Float
    /// Distance from the lens to the plane of sharp focus, measured along the
    /// view direction.
    public var focusDistance: Float

    /// Creates a camera. The focus distance defaults to the distance to
    /// `target`.
    public init(position: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
                verticalFieldOfView: Float = 40, aperture: Float = 0, focusDistance: Float? = nil) {
        self.position = position
        self.target = target
        self.up = up
        self.verticalFieldOfView = verticalFieldOfView
        self.aperture = aperture
        self.focusDistance = focusDistance ?? length(target - position)
    }

    /// Unit vector from the camera toward its target.
    public var viewDirection: SIMD3<Float> {
        normalize(target - position)
    }

    /// This camera adapted to an image of `aspectRatio` (width / height).
    ///
    /// The field of view is authored for `referenceAspectRatio`. Wider images
    /// keep the vertical field of view and show more on the sides. Narrower
    /// images widen it so the horizontal framing stays the same and nothing
    /// important is cropped.
    public func framed(forAspectRatio aspectRatio: Float, referenceAspectRatio: Float) -> TracerCamera {
        guard aspectRatio > 0, referenceAspectRatio > 0, aspectRatio < referenceAspectRatio else { return self }
        let halfVertical = verticalFieldOfView * Float.pi / 360
        let halfHorizontal = atan(tan(halfVertical) * referenceAspectRatio)
        var camera = self
        camera.verticalFieldOfView = min(2 * atan(tan(halfHorizontal) / aspectRatio) * 180 / Float.pi, 150)
        return camera
    }

    /// The ray through the lens center that lands on normalized image
    /// coordinates `(x, y)`. Here `(0, 0)` is the top-left corner and `(1, 1)`
    /// the bottom-right. The ray ignores depth of field, which makes it right
    /// for picking.
    public func centerRay(x: Float, y: Float, aspectRatio: Float) -> TracerRay {
        let rig = CameraRig(camera: self, aspectRatio: aspectRatio)
        let ray = rig.ray(x: x, y: y, lens: .zero)
        return TracerRay(origin: ray.origin, direction: ray.direction)
    }
}

/// Allowed ranges for an orbiting camera. Angles are in radians.
public struct TracerOrbitLimits: Sendable, Equatable {
    /// Allowed yaw, or `nil` for unrestricted spinning.
    public var yaw: ClosedRange<Float>?
    public var pitch: ClosedRange<Float>
    public var distance: ClosedRange<Float>

    public init(yaw: ClosedRange<Float>? = nil,
                pitch: ClosedRange<Float> = -0.2...1.45,
                distance: ClosedRange<Float> = 0.5...100) {
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
    }
}

/// Spherical camera coordinates around a target, which make mouse orbiting
/// and dollying simple.
public struct TracerOrbit: Sendable, Equatable {
    public var target: SIMD3<Float>
    /// Rotation about +Y in radians. At 0 the camera sits on the +Z side of
    /// the target, looking toward −Z.
    public var yaw: Float
    /// Elevation in radians. Positive values look down on the target.
    public var pitch: Float
    public var distance: Float

    public init(target: SIMD3<Float>, yaw: Float, pitch: Float, distance: Float) {
        self.target = target
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
    }

    /// Derives orbit coordinates from a camera's position and target.
    public init(camera: TracerCamera) {
        let offset = camera.position - camera.target
        let d = max(length(offset), 1e-4)
        target = camera.target
        distance = d
        pitch = asin(min(max(offset.y / d, -1), 1))
        yaw = atan2(offset.x, offset.z)
    }

    /// The camera position these coordinates describe.
    public var position: SIMD3<Float> {
        let horizontal = cos(pitch) * distance
        return target + SIMD3<Float>(sin(yaw) * horizontal, sin(pitch) * distance, cos(yaw) * horizontal)
    }

    /// The orbit clamped into `limits`.
    public func clamped(to limits: TracerOrbitLimits) -> TracerOrbit {
        var result = self
        if let yawRange = limits.yaw {
            result.yaw = min(max(yaw, yawRange.lowerBound), yawRange.upperBound)
        }
        result.pitch = min(max(pitch, limits.pitch.lowerBound), limits.pitch.upperBound)
        result.distance = min(max(distance, limits.distance.lowerBound), limits.distance.upperBound)
        return result
    }

    /// A camera at this orbit position. It keeps the lens settings of
    /// `lens`.
    public func camera(lens: TracerCamera) -> TracerCamera {
        var camera = lens
        camera.position = position
        camera.target = target
        camera.up = SIMD3<Float>(0, 1, 0)
        return camera
    }
}

/// Per-pass camera constants: the image plane placed at the focus distance,
/// plus lens axes pre-scaled by the lens radius.
struct CameraRig {
    let origin: Vec3
    let topLeft: Vec3
    let horizontal: Vec3
    let vertical: Vec3
    let lensRight: Vec3
    let lensUp: Vec3
    let hasLens: Bool
    /// Unit vector along the view direction.
    let forward: Vec3

    init(camera: TracerCamera, aspectRatio: Float) {
        var back = normalize(camera.position - camera.target)
        if lengthSquared(back) == 0 { back = Vec3(0, 0, 1) }
        var right = cross(camera.up, back)
        if lengthSquared(right) < 1e-12 {
            // Looking straight along `up`. Choose any perpendicular axis.
            right = cross(abs(back.y) < 0.9 ? Vec3(0, 1, 0) : Vec3(1, 0, 0), back)
        }
        right = normalize(right)
        let trueUp = cross(back, right)

        let fov = min(max(camera.verticalFieldOfView, 1), 170) * Float.pi / 180
        let focus = max(camera.focusDistance, 1e-3)
        let height = 2 * tan(fov / 2) * focus
        let width = height * max(aspectRatio, 1e-3)

        origin = camera.position
        forward = -back
        horizontal = right * width
        vertical = trueUp * (-height)
        topLeft = camera.position - back * focus - horizontal * 0.5 - vertical * 0.5
        let lensRadius = max(camera.aperture, 0) / 2
        hasLens = lensRadius > 0
        lensRight = right * lensRadius
        lensUp = trueUp * lensRadius
    }

    /// A primary ray for image coordinates in `[0, 1]²` (y pointing down) and a
    /// point on the unit lens disk.
    @inline(__always)
    func ray(x: Float, y: Float, lens: SIMD2<Float>) -> (origin: Vec3, direction: Vec3) {
        let focusPoint = topLeft + horizontal * x + vertical * y
        let start = origin + lensRight * lens.x + lensUp * lens.y
        return (start, normalize(focusPoint - start))
    }
}
