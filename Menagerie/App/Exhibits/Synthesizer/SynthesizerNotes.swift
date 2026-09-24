extension ExhibitNotes {
    static let synthesizer = ExhibitNotes(
        lede: "A polyphonic synthesizer written from scratch in Swift: eight voices of band-limited oscillators, a zero-delay-feedback filter and a studio effects chain, computed sample by sample on the real-time audio thread.",
        sections: [
            Section(
                title: "Oscillators without aliasing",
                body: "A naive sawtooth jumps instantly, spraying harmonics past Nyquist that fold back as inharmonic whine. Each jump is instead patched with **PolyBLEP**, a two-sample polynomial approximation of a band-limited step; triangles get its integral, **PolyBLAMP**, at their corners. The *supersaw* runs seven PolyBLEP saws in `SIMD8` lanes, detuned by ratios measured from the Roland JP-8000."
            ),
            Section(
                title: "A filter built to be swept",
                body: "The filter is a **topology-preserving transform** state-variable filter (Zavalishin, Simper). Its trapezoidal integrators close a zero-delay feedback loop that is solved exactly, so it keeps the analog response and stays stable while envelopes and the LFO sweep it at audio rate. Modulation adds up in octaves, then `tan(πf/fs)` pre-warps the cutoff."
            ),
            Section(
                title: "Real time, without waiting",
                body: "The render callback never allocates or blocks. Notes and patch edits cross from the UI through a small queue behind a mutex the audio thread only ever *tries*; if it's busy, that buffer simply catches up on the next one. Patches are plain structs, so taking one is a `memcpy`. Stolen voices fade over 3 ms and parameters glide, so nothing clicks."
            ),
            Section(
                title: "Space: chorus, echo and a delay network",
                body: "A Juno-style chorus widens the voices and echoes ping-pong between the speakers, darkening as they repeat. The reverb is an eight-line **feedback delay network**: prime-length delays mixed by a Hadamard matrix. The matrix is orthogonal, so the loop loses no energy until each line's gain sets the decay time, and slowly drifting taps keep the tail from ringing."
            ),
            Section(
                title: "The piece that writes itself",
                body: "*Play me something* runs a seeded composer. Every chord belongs to the key's Aeolian or Dorian mode, pad voicings are searched for the smallest movement with no semitone clashes, and arpeggios play only chord tones, so the dice can't pick a wrong note. Events are scheduled to the exact sample inside the render loop, and a seed always replays the same piece."
            ),
        ]
    )
}
