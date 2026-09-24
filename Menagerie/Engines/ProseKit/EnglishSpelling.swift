/// The spelling rules behind `SyllableCounter`, applied to one lowercase
/// word spelled with the ASCII letters a–z.
///
/// The count starts at one syllable per vowel group, then applies three kinds
/// of correction: splits inside vowel groups that span two syllables
/// ("li-on"), silent endings ("make", "jumped"), and syllabic consonants
/// ("rhythm", "prism").
enum EnglishSpelling {
    /// Syllables in `word`, never less than one.
    ///
    /// - Parameters:
    ///   - stressedFinalE: the word's last *e* was written *é*, as in "café",
    ///     so it is never silent.
    ///   - forcedSplits: positions of vowels written with a diaeresis, as in
    ///     "naïve", which always begin a new syllable.
    ///   - pronouncedEd: keep a final *-ed* syllable, for roots taken from
    ///     "-edly" and "-edness" ("supposedly").
    static func syllables(
        in word: [UInt8],
        stressedFinalE: Bool = false,
        forcedSplits: Set<Int> = [],
        pronouncedEd: Bool = false
    ) -> Int {
        let letters = Letters(word)
        guard letters.count > 0 else { return 0 }
        let nucleus = (0..<letters.count).map { isNucleus(letters, at: $0) }
        let prefixSplit = prefixSplits.first(where: { letters.hasPrefix($0.prefix) })?.at

        var count = 0
        for index in 0..<letters.count where nucleus[index] {
            if index == 0 || !nucleus[index - 1] || index == prefixSplit || forcedSplits.contains(index)
                || splitsVowelPair(letters, at: index, nucleus: nucleus) {
                count += 1
            }
        }

        if count > 1, hasSilentEnding(letters, nucleus: nucleus, stressedFinalE: stressedFinalE, pronouncedEd: pronouncedEd) {
            count -= 1
        }
        if hasSyllabicConsonantEnding(letters) {
            count += 1
        }
        return max(1, count)
    }

    // MARK: - Vowel sounds

    /// Whether the letter at `index` is the core of a syllable. Plain vowels
    /// always are; *y* depends on its neighbors.
    private static func isNucleus(_ w: Letters, at index: Int) -> Bool {
        let letter = w[index]
        if isVowelLetter(letter) { return true }
        guard letter == .y, index > 0 else { return false }   // "yes", "you"
        let next = w[index + 1]
        guard isVowelLetter(next) else { return true }        // "gym", "happy", "type"
        if endsInYe(w, yAt: index) { return true }            // "bye", "dyes", "played"
        if isVowelLetter(w[index - 1]) { return false }       // "player", "beyond", "mayor"
        if w.hasSuffix("ying") && index == w.count - 4 { return true }  // "copying", "studying"
        // After a consonant cluster, or as the first vowel, y is a vowel that
        // is followed by a second syllable ("dry-er", "cry-ing"); after a
        // single consonant it glides into the next vowel ("can-yon", "law-yer").
        return index == 1 || !isVowelLetter(w[index - 2])
    }

    /// "bye", "dye", "eyes", "stayed": a *y* before a final *e*, *es* or *ed*
    /// merges with it into one vowel sound.
    private static func endsInYe(_ w: Letters, yAt index: Int) -> Bool {
        let n = w.count
        if index == n - 2 && w[n - 1] == .e { return true }
        if index == n - 3 && w[n - 2] == .e && (w[n - 1] == .s || w[n - 1] == .d) { return true }
        return false
    }

    /// Whether the vowel at `index` starts a new syllable even though the
    /// letter before it is also a vowel.
    private static func splitsVowelPair(_ w: Letters, at index: Int, nucleus: [Bool]) -> Bool {
        let first = w[index - 1]
        let second = w[index]
        let before = w[index - 2]
        let after = w[index + 1]
        let n = w.count
        let hasEarlierVowel = nucleus[..<(index - 1)].contains(true)
        let isLast = index == n - 1
        let isLastBeforeS = index == n - 2 && w[n - 1] == .s

        // y as a vowel, then another vowel: "dry-er", "cry-ing", "em-bry-o".
        if first == .y {
            return !endsInYe(w, yAt: index - 1)
        }
        // A vowel before the suffix -ing: "be-ing", "go-ing", "ski-ing".
        if second == .i, w.hasSuffix("ing", endingAt: index + 2) || w.hasSuffix("ings", endingAt: index + 3) {
            return true
        }

        switch (first, second) {
        case (.i, .a):
            if after == .t {                                               // "appreci-ate", "hi-atus"
                return !w.matches("iv", at: index + 2)                     // but "ini-tia-tive"
            }
            if w.matches("lit", at: index + 1) { return true }             // "con-fi-den-ti-al-i-ty"
            if [.c, .t, .s, .g].contains(before) { return false }         // "so-cial", "Chris-tian", "A-sia"
            if before == .l, isVowelLetter(w[index - 3]) || w[index - 3] == .l {
                // "Ital-ian", "famil-iar", "Austral-ia"; but "re-li-able".
                let ending = isLast || (after == .n && (index + 2 == n || (w[index + 2] == .s && index + 3 == n)))
                    || (after == .r && index + 2 == n)
                if ending { return false }
            }
            if after == .g, w[index + 2] == .e { return false }            // "mar-riage"
            if before == .n, [.r, .i, .o, .u].contains(w[index - 3]),
               isLast || (after == .n && (index + 2 == n || (w[index + 2] == .s && index + 3 == n))) {
                return false                                               // "Cal-i-for-nia", "pneu-mo-nia"
            }
            return true                                                    // "pi-a-no", "di-al", "ma-ni-a"
        case (.i, .o):
            if w.matches("log", at: index + 1) { return true }             // "so-ci-ol-o-gy", "phys-i-ol-o-gy"
            if [.t, .s, .c, .g, .x, .n].contains(before) { return false } // "na-tion", "re-gion", "on-ion"
            if before == .h, w[index - 3] == .s { return false }           // "fash-ion"
            if before == .l, !isLast, isVowelLetter(w[index - 3]) || w[index - 3] == .l {
                return false                                               // "mil-lion", "pa-vil-ion"
            }
            return true                                                    // "li-on", "ra-di-o", "vi-o-lin"
        case (.i, .u):
            return before != .g                                            // "stad-i-um"; but "Bel-gium"
        case (.i, .i):
            return true                                                    // "ra-di-i"
        case (.i, .e):
            if hasEarlierVowel {
                // Comparatives and agent nouns: "hap-pi-er", "eas-i-est", "car-ri-ers".
                if (index == n - 2 && w.hasSuffix("ier"))
                    || (index == n - 3 && (w.hasSuffix("iers") || w.hasSuffix("iest"))) {
                    return true
                }
                // "a-li-en", "a-li-ens".
                if after == .n, index + 2 == n || (w[index + 2] == .s && index + 3 == n) {
                    return true
                }
            }
            if after == .t { return true }                                 // "qui-et", "so-ci-e-ty"
            if after == .n, w[index + 2] == .t || w[index + 2] == .c {
                if before == .c, w[index - 3] == .s { return true }        // "sci-ence"
                return ![.c, .t, .s].contains(before)                      // "cli-ent", "au-di-ence"; not "an-cient"
            }
            return false
        case (.e, .a):
            if hasEarlierVowel, isLast || isLastBeforeS, isVowelLetter(w[index - 3]) {
                return true                                                // "i-de-a", "ar-e-as"; not "over-seas"
            }
            if w.matches("creat", at: index - 3), !w.matches("ur", at: index + 2) { return true }  // "cre-ate"
            if w.matches("reali", at: index - 2) { return true }           // "re-al-i-ty"
            if w.matches("theat", at: index - 3) { return true }           // "the-a-ter"
            if hasEarlierVowel, before != .c, after == .n,
               index + 2 == n || (w[index + 2] == .s && index + 3 == n) {
                return true                                                // "Kor-e-an", "Eu-ro-pe-an"
            }
            return false
        case (.e, .o):
            if before == .g, index >= 3 || after == .r { return false }    // "gor-geous", "pi-geon", "Geor-gia"
            if before == .c { return false }                               // "her-ba-ceous"
            if before == .p, w[index - 3] == 0 { return false }            // "peo-ple"
            return true                                                    // "vid-e-o", "ne-on"
        case (.e, .u):
            if after == .m { return hasEarlierVowel }                      // "mu-se-um"
            if after == .s, index + 2 == n { return hasEarlierVowel }      // "nu-cle-us"
            return false
        case (.e, .i):
            // "a-the-ist", "the-ism", "de-ist".
            return after == .s && ((before == .h && w[index - 3] == .t) || before == .d)
        case (.u, .a):
            return before != .q && before != .g                            // "ac-tu-al"; not "qua", "gua"
        case (.u, .e):
            guard before != .q, before != .g else { return false }
            return after == .l || after == .n || after == .t               // "cru-el", "flu-ent", "du-et"
        case (.u, .i):
            guard before != .q, before != .g else { return false }
            if after == .d || after == .n { return true }                  // "flu-id", "ru-in"
            // "an-nu-i-ty", "tu-i-tion"; not "re-cruit-ing".
            return after == .t && (w[index + 2] == .y || (w[index + 2] == .i && w[index + 3] == .o))
        case (.u, .o):
            return before != .q                                            // "du-o", "con-tin-u-ous"
        case (.o, .e):
            return after == .m || after == .t || after == .l               // "po-em", "po-et", "No-el"
        case (.o, .i):
            // "he-ro-ic", "sto-i-cism", "he-ro-i-cal-ly"; not "choice".
            return after == .c && [0, .s, .i, .a].contains(w[index + 2])
        case (.a, .i):
            return after == .c && [0, .s].contains(w[index + 2])           // "mo-sa-ic"; not "Ja-mai-ca"
        case (.a, .o):
            return true                                                    // "cha-os"
        default:
            return false
        }
    }

    /// Prefixes that end in a vowel and meet a root that starts with one:
    /// "re-act", "co-op-er-ate". `at` is the position of the root's vowel.
    private static let prefixSplits: [(prefix: String, at: Int)] = [
        ("react", 2), ("reapp", 2), ("reass", 2), ("reawak", 2), ("reelect", 2), ("reenter", 2),
        ("reentr", 2), ("reestab", 2), ("reeval", 2), ("reexam", 2), ("reimb", 2), ("reimag", 2),
        ("reinc", 2), ("reinf", 2), ("reinst", 2), ("reint", 2), ("reinv", 2), ("reiter", 2),
        ("reopen", 2), ("reorder", 2), ("reorg", 2), ("reunit", 2), ("reunion", 2), ("reus", 2),
        ("preex", 3), ("preempt", 3), ("preord", 3), ("coexist", 2), ("cooperat", 2), ("coopt", 2),
        ("coord", 2), ("coauth", 2), ("coalit", 2), ("coerc", 2), ("zoolog", 2), ("deact", 2),
        ("deesc", 2), ("oasis", 1),
    ]

    // MARK: - Endings

    /// Whether the word ends in a vowel that spelling shows but speech
    /// drops: a silent *e* ("make"), *-es* ("makes"), *-ed* ("jumped"), or
    /// the *-ue* of "-gue" and "-que" ("league", "unique").
    private static func hasSilentEnding(_ w: Letters, nucleus: [Bool], stressedFinalE: Bool, pronouncedEd: Bool) -> Bool {
        let n = w.count
        guard n >= 3 else { return false }

        if w.hasSuffix("gue") || w.hasSuffix("que") || w.hasSuffix("gues") || w.hasSuffix("ques")
            || w.hasSuffix("gued") || w.hasSuffix("qued") {
            return true
        }

        // The e must be a vowel group of its own, after a consonant.
        func isLoneE(at index: Int) -> Bool {
            w[index] == .e && nucleus[index] && !nucleus[index - 1]
        }
        // "ta-ble" and "a-cre" keep the syllable that "whale" and "more" lose.
        func isSyllabicLeOrRe(endingAt index: Int) -> Bool {
            let liquid = w[index]
            guard liquid == .l || liquid == .r, index >= 1 else { return false }
            return !nucleus[index - 1] && w[index - 1] != liquid && w[index - 1] != 0
        }

        if w[n - 1] == .e, isLoneE(at: n - 1), !stressedFinalE {
            return !isSyllabicLeOrRe(endingAt: n - 2)
        }

        if w.hasSuffix("es"), n >= 4, isLoneE(at: n - 2), !stressedFinalE {
            let consonant = w[n - 3]
            let sibilant = [.s, .x, .z, .c, .g].contains(consonant)
                || (consonant == .h && (w[n - 4] == .c || w[n - 4] == .s))
            return !sibilant && !isSyllabicLeOrRe(endingAt: n - 3)
        }

        if w.hasSuffix("ed"), n >= 4, isLoneE(at: n - 2), !pronouncedEd {
            let consonant = w[n - 3]
            if consonant == .t || consonant == .d { return false }        // "want-ed", "need-ed"
            return !isSyllabicLeOrRe(endingAt: n - 3)                     // "han-dled", "hun-dred"
        }
        return false
    }

    /// Endings where a consonant carries a syllable of its own: "pris-m",
    /// "sar-cas-m", "rhy-thm".
    private static func hasSyllabicConsonantEnding(_ w: Letters) -> Bool {
        for ending in ["sm", "sms"] where w.hasSuffix(ending) {
            let vowel = w[w.count - ending.count - 1]
            return vowel == .i || vowel == .a || vowel == .y
        }
        return w.hasSuffix("thm") || w.hasSuffix("thms")
    }

    // MARK: - Letters

    static func isVowelLetter(_ letter: UInt8) -> Bool {
        letter == .a || letter == .e || letter == .i || letter == .o || letter == .u
    }
}

/// A word's letters with bounds-safe access: positions outside the word read
/// as 0, which matches no letter.
struct Letters {
    let bytes: [UInt8]

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var count: Int { bytes.count }

    subscript(index: Int) -> UInt8 {
        index >= 0 && index < bytes.count ? bytes[index] : 0
    }

    func hasPrefix(_ prefix: String) -> Bool {
        matches(prefix, at: 0)
    }

    func hasSuffix(_ suffix: String) -> Bool {
        matches(suffix, at: bytes.count - suffix.utf8.count)
    }

    /// Whether `suffix` ends exactly at `index` and nothing follows it.
    func hasSuffix(_ suffix: String, endingAt index: Int) -> Bool {
        index == bytes.count - 1 && hasSuffix(suffix)
    }

    func matches(_ pattern: String, at start: Int) -> Bool {
        guard start >= 0, start + pattern.utf8.count <= bytes.count else { return false }
        return zip(bytes[start...], pattern.utf8).allSatisfy { $0 == $1 }
    }
}

extension UInt8 {
    // Lowercase ASCII letters, for readable spelling rules.
    fileprivate static let a = UInt8(ascii: "a")
    fileprivate static let c = UInt8(ascii: "c")
    fileprivate static let d = UInt8(ascii: "d")
    fileprivate static let e = UInt8(ascii: "e")
    fileprivate static let g = UInt8(ascii: "g")
    fileprivate static let h = UInt8(ascii: "h")
    fileprivate static let i = UInt8(ascii: "i")
    fileprivate static let l = UInt8(ascii: "l")
    fileprivate static let m = UInt8(ascii: "m")
    fileprivate static let n = UInt8(ascii: "n")
    fileprivate static let o = UInt8(ascii: "o")
    fileprivate static let p = UInt8(ascii: "p")
    fileprivate static let q = UInt8(ascii: "q")
    fileprivate static let r = UInt8(ascii: "r")
    fileprivate static let s = UInt8(ascii: "s")
    fileprivate static let t = UInt8(ascii: "t")
    fileprivate static let u = UInt8(ascii: "u")
    fileprivate static let x = UInt8(ascii: "x")
    fileprivate static let y = UInt8(ascii: "y")
    fileprivate static let z = UInt8(ascii: "z")
}
