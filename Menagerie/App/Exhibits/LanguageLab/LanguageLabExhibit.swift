import SwiftUI

/// Language Lab: on-device linguistics. Apple's NaturalLanguage framework
/// finds languages, names, parts of speech, sentiment and meaning; the
/// portable ProseKit engine adds syllables, readability formulas, lexical
/// diversity and RAKE key phrases.
struct LanguageLabExhibit: View {
    @State private var model = LanguageLab.Model()

    var body: some View {
        ExhibitLayout(.languageLab) {
            LanguageLab.StageView(model: model)
        } controls: {
            LanguageLab.SamplePicker(model: model)
            LanguageLab.ModePicker(model: model)
            LanguageLab.EmbeddingPlayground(model: model)
            LanguageLab.ReadabilityPanel(model: model)
            LanguageLab.StatisticsPanel(model: model)
        }
        .onAppear {
            model.start()
        }
    }
}

/// A namespace that keeps the exhibit's many small types out of the app
/// module's shared namespace.
enum LanguageLab {}
