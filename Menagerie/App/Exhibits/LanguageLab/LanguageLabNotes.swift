extension ExhibitNotes {
    static let languageLab = ExhibitNotes(
        lede: "Everything here is computed on your Mac. Apple’s NaturalLanguage framework supplies the trained models, and ProseKit, a small Swift library with no dependencies, supplies the classic text statistics that need no model at all.",
        sections: [
            Section(
                title: "Tagging words",
                body: "`NLTagger` walks the text under different *tag schemes*. `.nameType` with `.joinNames` merges “Maria Delgado” into one person; `.lexicalClass` gives each word its part of speech; `.lemma` gives its dictionary form. `.sentimentScore` rates each sentence from −1 to +1, and `NLLanguageRecognizer` weighs every language it knows."
            ),
            Section(
                title: "Meaning as geometry",
                body: "`NLEmbedding` maps words to vectors, and related words point the same way. Neighbors are the nearest vectors by cosine distance. Analogies are arithmetic: normalize *king*, subtract *man*, add *woman*, then find the nearest word that isn’t one of the three. Sentence embeddings do the same for whole sentences, which lights up the similarity heatmap."
            ),
            Section(
                title: "Counting syllables",
                body: "Readability formulas need syllables, and English spelling hides them. ProseKit counts vowel groups, then corrects for silent *e*, the *-le*, *-es* and *-ed* endings, *y* as a vowel or a glide, and vowel pairs that split (*li-on*, *cre-ate*). It agrees with the CMU Pronouncing Dictionary on 98.7% of common words."
            ),
            Section(
                title: "Six formulas",
                body: "Flesch, Flesch–Kincaid, Gunning Fog, SMOG, Coleman–Liau and ARI all weigh sentence length against word length, measured in syllables or letters. They disagree, so the consensus grade averages the five grade levels. *Difficulty* mode scores every sentence on its own, so the long, knotted ones stand out."
            ),
            Section(
                title: "RAKE key phrases",
                body: "Rapid Automatic Keyword Extraction splits the text at stopwords and punctuation into candidate phrases. Each word scores its **degree**, the total length of the phrases it appears in, over its **frequency**, so words that live in long phrases beat common loners. A phrase scores the sum of its words."
            ),
        ]
    )
}
