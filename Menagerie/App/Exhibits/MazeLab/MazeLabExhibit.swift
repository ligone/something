import SwiftUI

/// Maze Lab: carve mazes with classic generation algorithms, then watch
/// search algorithms explore them.
///
/// On opening, it carves a maze with the recursive backtracker and then runs
/// A*. After that, every edit re-runs the latest search instantly, so the
/// route follows the user's brush.
struct MazeLabExhibit: View {
    @State private var model = MazeLabModel()

    var body: some View {
        ExhibitLayout(.mazeLab) {
            MazeStage(model: model)
                .stageHUD {
                    MazeHUD(model: model)
                }
                .stageHint(model.hint)
        } controls: {
            MazeGenerateSection(model: model)
            MazeSearchSection(model: model)
            MazePaintSection(model: model)
            MazeCompareSection(model: model)
        }
        .onAppear {
            model.begin(captureTour: AppEnvironment.isCaptureTour)
        }
        .onDisappear {
            model.end()
        }
    }
}
