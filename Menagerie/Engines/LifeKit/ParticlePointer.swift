/// A radial force field centered on a point, such as the user's mouse.
///
/// Inside ``radius`` the field pulls particles toward its center (or pushes
/// them away when ``strength`` is negative) and drags them along with the
/// pointer's own motion, so sweeping the pointer stirs the soup. Both effects
/// fade linearly to nothing at the rim.
public struct ParticlePointer: Hashable, Sendable {
    /// The center, in world coordinates.
    public var x: Float
    public var y: Float

    /// The reach of the field, in world units.
    public var radius: Float

    /// The acceleration at the center, in world units per second squared.
    /// Positive values attract and negative values repel.
    public var strength: Float

    /// The pointer's velocity, in world units per second.
    public var velocityX: Float
    public var velocityY: Float

    /// How quickly particles match the pointer's velocity, per second.
    public var stirring: Float

    /// Creates a pointer field.
    public init(
        x: Float,
        y: Float,
        radius: Float = 0.25,
        strength: Float = 8,
        velocityX: Float = 0,
        velocityY: Float = 0,
        stirring: Float = 10
    ) {
        self.x = x
        self.y = y
        self.radius = radius
        self.strength = strength
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.stirring = stirring
    }

    /// Whether every field is finite and the radius is positive.
    var isUsable: Bool {
        x.isFinite && y.isFinite && radius.isFinite && radius > 0 && strength.isFinite
            && velocityX.isFinite && velocityY.isFinite && stirring.isFinite
    }
}
