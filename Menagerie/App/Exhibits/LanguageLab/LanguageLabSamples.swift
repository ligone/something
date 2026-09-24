extension LanguageLab {
    /// Texts chosen so each analysis has something to find.
    enum Sample: String, CaseIterable, Identifiable {
        case news, review, literary, multilingual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .news: "News report"
            case .review: "Product review"
            case .literary: "Moby-Dick"
            case .multilingual: "Multilingual"
            }
        }

        var caption: String {
            switch self {
            case .news: "Dense with names"
            case .review: "Praise, then fury"
            case .literary: "Melville, 1851"
            case .multilingual: "Eight languages"
            }
        }

        var symbol: String {
            switch self {
            case .news: "newspaper"
            case .review: "star.leadinghalf.filled"
            case .literary: "book.closed"
            case .multilingual: "globe"
            }
        }

        var text: String {
            switch self {
            case .news: Self.newsText
            case .review: Self.reviewText
            case .literary: Self.literaryText
            case .multilingual: Self.multilingualText
            }
        }

        /// A fictional report, packed with people, places and organizations.
        private static let newsText = """
            The European Space Agency and NASA announced on Tuesday that a new climate \
            satellite will launch from French Guiana next spring. Speaking in Paris, mission \
            scientist Maria Delgado said the spacecraft would measure rising seas from Lagos to \
            Jakarta with millimeter precision. Her colleague Kenji Watanabe, who leads the \
            ground team in Tokyo, called it “the most precise ruler ever flown.” Airbus \
            assembled the satellite in Toulouse, while Microsoft will process its data in the \
            cloud. The World Bank plans to share the measurements with coastal cities across \
            Africa and South Asia, according to Delgado.
            """

        /// A review that starts in love and ends in anger.
        private static let reviewText = """
            I wanted to love these headphones, and for the first week I did. The sound is \
            stunning: warm, rich bass and crystal-clear vocals that made my old records feel \
            brand new. Noise cancellation is superb on trains and planes, and the leather case \
            is gorgeous. Then the problems started. The left earcup began crackling after ten \
            days, and the battery now dies in barely three hours. Customer support was useless, \
            rude and painfully slow, and they refused to replace a clearly defective product. \
            For this price, that is unacceptable. If you find a pair that works, you will adore \
            them; I just can’t recommend gambling three hundred dollars on it.
            """

        /// The opening paragraph of Moby-Dick, as Project Gutenberg prints it.
        private static let literaryText = """
            Call me Ishmael. Some years ago—never mind how long precisely—having little or no \
            money in my purse, and nothing particular to interest me on shore, I thought I would \
            sail about a little and see the watery part of the world. It is a way I have of \
            driving off the spleen and regulating the circulation. Whenever I find myself \
            growing grim about the mouth; whenever it is a damp, drizzly November in my soul; \
            whenever I find myself involuntarily pausing before coffin warehouses, and bringing \
            up the rear of every funeral I meet; and especially whenever my hypos get such an \
            upper hand of me, that it requires a strong moral principle to prevent me from \
            deliberately stepping into the street, and methodically knocking people’s hats \
            off—then, I account it high time to get to sea as soon as I can. This is my \
            substitute for pistol and ball. With a philosophical flourish Cato throws himself \
            upon his sword; I quietly take to the ship. There is nothing surprising in this. If \
            they but knew it, almost all men in their degree, some time or other, cherish very \
            nearly the same feelings towards the ocean with me.
            """

        /// One sentence per line: English, French, German, Spanish, Russian,
        /// Japanese, Chinese and Korean.
        private static let multilingualText = """
            Every language is a different window onto the same world.
            Le petit café au coin de la rue ouvre à sept heures, et l’odeur du pain chaud remplit tout le quartier.
            Im Winter trinken wir heißen Tee am Fenster und sehen zu, wie der Schnee langsam die Stadt bedeckt.
            Mi abuela cantaba canciones antiguas mientras cocinaba, y todavía recuerdo cada palabra.
            Москва — огромный город, который никогда не спит.
            東京の夜は明るくて、どこへ行っても人がたくさんいます。
            我每天早上喝一杯咖啡，然后去公园散步。
            서울의 봄은 벚꽃으로 가득합니다.
            """
    }
}
