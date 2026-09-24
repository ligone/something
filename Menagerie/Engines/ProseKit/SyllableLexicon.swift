/// The word lists behind `SyllableCounter`.
enum SyllableLexicon {
    /// Words whose spelling misleads every rule. Counts follow standard
    /// dictionary pronunciations.
    static let exceptions: [String: Int] = [
        // Silent letters and swallowed vowels.
        "business": 2, "businesses": 3, "businessman": 3, "businessmen": 3, "colonel": 2,
        "every": 2, "wednesday": 2, "wednesdays": 2, "aisle": 1, "aisles": 1, "isle": 1, "isles": 1,
        "whereas": 2, "whereby": 2, "thereby": 2, "therefore": 2, "moreover": 3, "furthermore": 3,
        "nevertheless": 4, "whoever": 3, "whomever": 3, "maybe": 2, "ok": 2, "evening": 2,
        "evenings": 2, "william": 2, "williams": 2, "parliament": 3, "parliaments": 3,
        "parliamentary": 5, "guinea": 2, "sierra": 3, "tokyo": 3, "louis": 2, "anime": 3,
        "diabetes": 4, "hercules": 3, "socrates": 3, "achilles": 3, "thereof": 2, "hereby": 2,
        "herein": 2, "genius": 2, "geniuses": 3, "christianity": 5, "zimbabwe": 3, "chile": 2,
        "watershed": 3, "bloodshed": 2,
        // A final e that is pronounced.
        "recipe": 3, "recipes": 3, "acne": 2, "adobe": 3, "anemone": 4, "apostrophe": 4,
        "catastrophe": 4, "coyote": 3, "coyotes": 3, "epitome": 4, "facsimile": 4, "finale": 3,
        "hyperbole": 4, "karate": 3, "karaoke": 4, "sesame": 3, "simile": 3, "similes": 3,
        "tamale": 3, "guacamole": 4, "abalone": 4, "posse": 2, "ukulele": 4, "cafe": 2,
        "cafes": 2, "cliche": 2, "cliches": 2, "fiance": 3, "fiancee": 3,
        "nike": 2, "chloe": 2, "zoe": 2, "phoebe": 2, "penelope": 4,
        // Adjectives that pronounce -ed.
        "naked": 2, "wicked": 2, "crooked": 2, "rugged": 2, "ragged": 2, "jagged": 2,
        "wretched": 2, "beloved": 3, "embed": 2, "embeds": 2, "infrared": 3,
        // -ue that is not silent after g.
        "argue": 2, "argued": 2, "argues": 2, "ague": 2, "segue": 2, "segued": 2,
        // Vowel pairs the general rules split or join wrongly.
        "giant": 2, "giants": 2, "brilliant": 2, "brilliantly": 3, "soldier": 2, "soldiers": 2,
        "frontier": 2, "frontiers": 2, "cashier": 2, "cashiers": 2, "glacier": 2, "glaciers": 2,
        "premier": 2, "premiere": 2, "ratio": 3, "ratios": 3, "patio": 3, "patios": 3,
        "behavior": 3, "behaviors": 3, "behaviour": 3, "behaviours": 3, "behavioral": 4,
        "behavioural": 4, "savior": 2, "saviour": 2, "george": 1, "leopard": 2, "leopards": 2,
        "jeopardy": 3, "righteous": 2, "yeoman": 2, "persuade": 2, "persuaded": 3, "persuades": 2,
        "persuasion": 3, "persuasive": 3, "dissuade": 2, "suave": 1, "naive": 2, "linear": 3,
        "nuclear": 3, "extraordinary": 5, "extraordinarily": 6, "polyester": 4, "lineage": 3,
        "suicide": 3, "suicides": 3, "science": 2, "conscience": 2, "fruity": 2, "shoelace": 2,
        "shoelaces": 3, "bluetooth": 2,
        // Compounds whose silent e the prefix rules can't see.
        "makeup": 2, "makeover": 3, "takeover": 3, "takeoff": 2, "takeout": 2, "takeaway": 3,
        "timeout": 2, "timeouts": 2, "lineup": 2, "lineups": 2, "homeowner": 3, "homeowners": 3,
        "forever": 3, "forensic": 3, "forensics": 3, "forester": 3, "forestry": 3, "placebo": 3,
        "facetious": 3, "element": 3, "elements": 3, "increment": 3, "increments": 3,
        "decrement": 3, "vehement": 3, "tenement": 3, "clement": 2, "excrement": 3,
        // Common abbreviations said as words.
        "mr": 2, "mrs": 2, "ms": 1, "dr": 2, "st": 1, "jr": 2, "sr": 2, "vs": 2, "etc": 4,
    ]

    /// Suffixes whose syllable count doesn't depend on the root, so a root
    /// like "hope" in "hopeless" keeps its silent e.
    static let suffixes: [(ending: [UInt8], syllables: Int)] = {
        let table: [(String, Int)] = [
            ("nesses", 2), ("ments", 1), ("ment", 1), ("ness", 1), ("less", 1), ("fuls", 1), ("ful", 1),
            ("things", 1), ("thing", 1), ("where", 1), ("body", 2), ("times", 1), ("time", 1),
            ("some", 1), ("ones", 1), ("one", 1), ("what", 1), ("how", 1), ("days", 1), ("day", 1),
            ("ly", 1),
        ]
        return table.map { (ending: Array($0.0.utf8), syllables: $0.1) }
    }()

    /// One-syllable words ending in a silent e that start compounds:
    /// "home-work", "base-ball", "life-style".
    static let compoundPrefixes: [[UInt8]] = [
        "base", "bone", "brace", "cake", "care", "code", "face", "file", "fire", "fore", "frame",
        "game", "gate", "grape", "grave", "guide", "hate", "home", "hope", "horse", "house", "ice",
        "lake", "life", "like", "line", "live", "lone", "love", "make", "name", "nine", "note",
        "pipe", "place", "safe", "score", "shape", "share", "shore", "side", "slide", "smoke",
        "some", "space", "spoke", "stage", "stake", "state", "stone", "store", "take", "time",
        "trade", "type", "ware", "wave", "white", "whole", "wide", "wine", "wire", "wise",
    ].map { Array($0.utf8) }

    /// Splits a word into a root and a known suffix, provided the root is
    /// still a plausible word. A final "i" in the root reverts to "y", so
    /// "happiness" becomes "happy" + "ness".
    static func suffixSplit(_ letters: [UInt8]) -> (root: [UInt8], syllables: Int, keepsEd: Bool)? {
        for (ending, syllables) in suffixes {
            guard letters.count >= ending.count + 2, letters.suffix(ending.count).elementsEqual(ending) else {
                continue
            }
            var root = Array(letters.dropLast(ending.count))
            guard hasVowel(root) else { continue }
            if root.last == UInt8(ascii: "i") {
                root[root.count - 1] = UInt8(ascii: "y")
            }
            // "suppos-ed-ly" and "prepar-ed-ness" pronounce their -ed.
            let keepsEd = root.count > 3 && root.suffix(2).elementsEqual("ed".utf8)
            return (root, syllables, keepsEd)
        }
        return nil
    }

    /// The part of a compound after a silent-e prefix, when there is one.
    static func compoundRemainder(_ letters: [UInt8]) -> [UInt8]? {
        for prefix in compoundPrefixes {
            guard letters.count >= prefix.count + 2, letters.starts(with: prefix) else { continue }
            let rest = Array(letters[prefix.count...])
            // A vowel or r after the e usually means the e is sounded:
            // "timer" and "career" are not compounds.
            guard let first = rest.first,
                  !EnglishSpelling.isVowelLetter(first),
                  first != UInt8(ascii: "r"),
                  hasVowel(rest) else { continue }
            return rest
        }
        return nil
    }

    private static func hasVowel(_ letters: [UInt8]) -> Bool {
        letters.enumerated().contains { index, letter in
            EnglishSpelling.isVowelLetter(letter) || (letter == UInt8(ascii: "y") && index > 0)
        }
    }
}
