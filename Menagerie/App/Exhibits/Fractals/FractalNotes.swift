extension ExhibitNotes {
    static let fractals = ExhibitNotes(
        lede: "Every pixel asks one question: if you start at zero and keep applying *z* ← *z*² + *c*, does *z* stay bounded or fly off to infinity? The answer draws the Mandelbrot set, and a fragment shader asks it millions of times per frame.",
        sections: [
            Section(
                title: "Smooth escape time",
                body: "Points outside the set are colored by how fast they escape. Counting whole iterations gives stripes, so the shader uses the *normalized* count `n + 1 − log₂(log |z|)` with a bailout radius of 256, then maps its square root through a cyclic gradient blended in **Oklab** for vivid, even color."
            ),
            Section(
                title: "Double-float arithmetic",
                body: "GPUs compute in 32-bit floats, which blur out near 10⁴× zoom. Past that point, each coordinate becomes an unevaluated sum of two floats, and the shader switches to error-free **TwoSum** and fused-multiply-add **TwoProduct**. That gives about 48 bits, enough for ten billion times. The shader is compiled with fast math off so the error terms survive."
            ),
            Section(
                title: "Minibrots and Newton's method",
                body: "The tour's deep stops are *minibrots*: tiny copies of the whole set. Their centers are found by running Newton's method on the orbit equation *f*ᶜᵖ(0) = 0. Tracking d*z*/d*c* alongside *z* supplies the derivative. The period comes from the orbit's closest approach to zero."
            ),
            Section(
                title: "Optimal flight paths",
                body: "Flights follow van Wijk and Nuij's optimal zoom-and-pan trajectory. When the camera travels, it pulls back so the motion reads at a constant perceived speed, then dives in again. The same curve handles a 4× nudge and a nine-order-of-magnitude plunge."
            ),
            Section(
                title: "Rendering on demand",
                body: "The fractal renders into an offscreen texture only when the view changes, and each frame composites it with the live Julia preview. While you drag at deep zoom the renderer drops to half resolution. At rest it refines to full resolution, and adds 2×2 supersampling wherever 32-bit math suffices."
            ),
        ]
    )
}
