import SortKit
import SwiftUI

/// Sound of Sorting, after Timo Bingmann's program of the same name: watch
/// and hear sorting algorithms work. Each array access lights up its bar and
/// plays a tone pitched by the value touched.
///
/// The model changes every frame while a sort plays, so every view that
/// reads the lanes is a small leaf (the stage, the HUD, the statistics).
/// This view reads none of them and isn't re-evaluated during playback.
struct SortingExhibit: View {
    @State private var model = SortingModel()
    @FocusState private var stageFocused: Bool

    var body: some View {
        ExhibitLayout(.sorting) {
            stage
        } controls: {
            SortingControls(model: model)
        }
        .defaultFocus($stageFocused, true)
        .onAppear {
            model.appear()
            stageFocused = true
        }
        .onDisappear {
            model.disappear()
        }
    }

    private var stage: some View {
        SortingStage(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                stageFocused = true
            }
            .focusable()
            .focusEffectDisabled()
            .focused($stageFocused)
            .onKeyPress(.space, phases: .down) { _ in
                model.togglePlay()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                model.step()
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "rR"), phases: .down) { _ in
                model.shuffle()
                return .handled
            }
            .stageHUD {
                SortingLeadingHUD(model: model)
            }
            .stageHUD(.topTrailing) {
                SortingTrailingHUD(model: model)
            }
            .stageHint("Space to play or pause  ·  → to step  ·  R to shuffle")
    }
}

/// Top left: what is sorting, and how much work it has done.
private struct SortingLeadingHUD: View {
    let model: SortingModel

    var body: some View {
        if model.isRacing {
            StatPill("Race", "\(model.lanes.count) algorithms")
            StatPill("Bars", "\(model.size)")
            StatPill("Step", compactCount(Double(model.lanes.map(\.counts.steps).max() ?? 0)))
        } else if let lane = model.primaryLane {
            StatPill("Algorithm", lane.algorithm.name)
            StatPill("Compares", compactCount(Double(lane.counts.comparisons)))
            StatPill("Writes", compactCount(Double(lane.counts.arrayWrites)))
        }
    }
}

/// Top right: the current pass and how far along it is.
private struct SortingTrailingHUD: View {
    let model: SortingModel

    var body: some View {
        if model.isRacing {
            let finished = model.lanes.filter { $0.phase == .sorted }.count
            StatPill("Finished", "\(finished) of \(model.lanes.count)")
        } else if let lane = model.primaryLane {
            if model.isPlaying, !lane.isPrepared {
                StatPill("Tracing", "…")
            }
            if let gap = lane.focus.gap {
                StatPill("Gap", "\(gap)")
            }
            if let digit = lane.focus.digit {
                StatPill("Digit", "\(digit + 1)")
            }
            switch lane.phase {
            case .waiting:
                StatPill("Bars", "\(lane.input.count)")
            case .sorting:
                StatPill("Progress", "\(Int((lane.progress * 100).rounded(.down)))%")
            case .verifying:
                StatPill("Verifying", "\(Int(lane.sweep))")
            case .sorted:
                StatPill("Sorted", lane.isVerified ? "✓" : "✗")
            }
        }
    }
}
