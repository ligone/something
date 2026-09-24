import CalculusKit
import SwiftUI

/// Type a function; get its exact derivatives, its roots, extrema and
/// inflection points, integrals and Taylor polynomials, all plotted live.
struct CalculusExhibit: View {
    @State private var model = CalculusModel()

    var body: some View {
        ExhibitLayout(.calculus) {
            VStack(spacing: 0) {
                CalculusExpressionBar(model: model)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
                CalculusPlotView(model: model)
            }
        } controls: {
            CalculusControls(model: model)
        }
        .onAppear {
            model.appear()
        }
        .onDisappear {
            model.stop()
        }
    }
}
