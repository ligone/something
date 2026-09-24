extension ExhibitNotes {
    static let pathTracer = ExhibitNotes(
        lede: "Every pixel is an average of random light paths, traced on all your CPU cores and refined many times a second. Watch the noise melt into soft shadows, color bleeding and caustics as the estimate converges.",
        sections: [
            .init(
                title: "Monte Carlo, one path at a time",
                body: "Each pass traces one path per pixel: a camera ray bounces through the scene in random directions and carries back the light it finds. Averaging passes converges on the rendering equation's answer, with noise falling as **1/√N**. **Russian roulette** ends dim paths early without bias, and at `4096` samples per pixel the finished image rests, using no CPU."
            ),
            .init(
                title: "Next-event estimation and MIS",
                body: "Hitting a small light by chance is rare, so at every diffuse bounce the tracer also sends a **shadow ray** toward a light chosen by power, and toward the sun. BSDF sampling and light sampling each shine where the other struggles, and the **power heuristic** blends them so every light is counted exactly once."
            ),
            .init(
                title: "Materials from first principles",
                body: "Diffuse surfaces use **cosine-weighted** sampling. Metals get Schlick-tinted reflectance plus fuzz. Glass follows **Snell's law**, picks reflection by Fresnel, switches to *total internal reflection* past the critical angle and absorbs light by **Beer–Lambert**. Lacquer layers a Fresnel clear coat over a colored base, like a billiard ball."
            ),
            .init(
                title: "A BVH and every core",
                body: "A **surface area heuristic** BVH lets rays skip whole clusters of marbles. Rows render in parallel with `DispatchQueue.concurrentPerform`, and each row seeds its own **PCG** stream from its index and sample count, so every run is bit-for-bit reproducible. Moving the camera cancels a pass mid-flight and restarts at preview resolution."
            ),
            .init(
                title: "A real lens, a filmic finish",
                body: "The camera is a **thin lens**: rays start across the aperture and meet on the focal plane. Clicking casts a pick ray and moves that plane to whatever it hits. Radiance has no upper limit, so an **ACES** filmic curve rolls off the highlights before sRGB encoding, and a faint dither keeps gradients free of banding."
            ),
        ]
    )
}
