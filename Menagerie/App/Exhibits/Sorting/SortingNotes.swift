extension ExhibitNotes {
    static let sorting = ExhibitNotes(
        lede: "Each algorithm sorts a copy of the array first, logging every comparison, swap, read and write. The stage then replays that log at any speed you like, lighting each touched bar and sounding its value as a pitch.",
        sections: [
            Section(
                title: "Traces, not threads",
                body: "Algorithms run against an instrumented array that records each `compare`, `swap`, `write` and `read`, plus markers for pivots, gaps and active ranges. A `SortReplayer` applies the log one operation at a time, so the same trace plays at one step a second or 50,000, rewinds for free, and races fairly: in **Race** mode every lane advances the same number of steps each frame, so the fewest steps wins."
            ),
            Section(
                title: "Hearing the values",
                body: "A touched value sounds a blip whose pitch rises exponentially from 120 Hz to 1.5 kHz, panned by position. A 16-voice synth inside `AVAudioSourceNode` renders sine–triangle tones with a 2 ms attack and a 30–80 ms decay. The audio thread only *tries* a lock to collect notes, so it never blocks, and fast sorts are thinned to six notes per frame: shimmer, not static."
            ),
            Section(
                title: "Pivots that behave",
                body: "Quick sort takes a median-of-three pivot, and on long ranges Tukey's *ninther*, a median of three medians. A plain median of three wasn't enough: each partition's final swap parks a large value at the front, so reversed input decays into runs like `[8, 1, 2, …, 7]`, where first, middle and last always pick the second largest. The test suite caught it going quadratic."
            ),
            Section(
                title: "Proving stability",
                body: "A stable sort keeps equal keys in their original order. The tests tag every element with its starting position in the low bits and sort on the high bits alone. Stable sorts must come out in exact tag order, and every sort labeled **unstable** must visibly break that order on some input, so the badges in the panel are checked facts."
            ),
            Section(
                title: "Why n² hurts",
                body: "On 128 random bars, quick sort needs about 1,300 steps and bubble sort 11,000. At 1,024 bars that becomes 14,000 against 780,000, and cycle sort, which makes at most n − 1 swaps, spends 1.5 million comparisons finding where they go. Radix sort never compares: five base-4 passes, each reading every value and writing it to its bucket."
            ),
        ]
    )
}
