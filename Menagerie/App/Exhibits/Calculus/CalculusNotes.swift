extension ExhibitNotes {
    static let calculus = ExhibitNotes(
        lede: "A small computer algebra system and a numerical toolkit, written from scratch. Whatever you type is parsed into a tree, differentiated exactly, simplified into the form you'd write by hand, then explored numerically.",
        sections: [
            Section(
                title: "Parsing with binding powers",
                body: "A **Pratt parser** gives every operator a binding power: `+` binds at 10, `·` at 20 and `^` at 30, so `-x^2` means `−(x²)` and `2^3^2` is 512. Writing things side by side multiplies them, which is how `2x`, `3sin(x)` and `(x+1)(x−1)` work. Errors record a character position, so the field can underline exactly what went wrong."
            ),
            Section(
                title: "Derivatives that look human",
                body: "Differentiation applies the sum, product and chain rules, treats `u/v` as `u·v⁻¹`, and handles `f^g` by writing it as `e^(g·ln f)`. The raw result is a mess, so a **simplifier** rewrites it until nothing changes: it folds exact fractions, collects like terms, merges powers and sorts terms canonically. That's how `(sin(x)·x²)′` becomes `x²·cos(x) + 2x·sin(x)`."
            ),
            Section(
                title: "Roots, extrema and poles",
                body: "A fine scan brackets every sign change and **Brent's method** polishes each one, pairing the safety of bisection with the speed of interpolation. Sign changes of `f′` are extrema, and those of `f″` are inflection points. Where `f` blows up instead of crossing zero, as `tan(x)` does, the candidate is rejected as a pole, and the plot breaks the curve rather than drawing a false wall."
            ),
            Section(
                title: "Integrals and Taylor series",
                body: "Areas come from **adaptive Simpson's rule**, which subdivides only where the estimate is still moving and steps around undefined points, so `∫₀¹ ln(x) dx = −1` works and `1/x` is flagged as divergent. Taylor coefficients come from **automatic differentiation** in power-series arithmetic, where each function has an exact recurrence, so order 12 takes microseconds with no symbolic blow-up."
            ),
            Section(
                title: "Fast enough to follow the pointer",
                body: "Plotting evaluates each function thousands of times a frame, so expressions are compiled into a flat program for a tiny **stack machine** instead of walking the tree. Moving the pointer redraws only a light overlay, and roots and integrals are computed off the main thread."
            ),
        ]
    )
}
