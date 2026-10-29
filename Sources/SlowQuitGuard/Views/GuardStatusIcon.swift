import SwiftUI

struct GuardStatusIcon: View {
    let model: ProtectionModel

    var body: some View {
        Image(systemName: model.displayState.symbol)
            .accessibilityLabel("SlowQuitGuard，" + model.displayState.title)
            .help("SlowQuitGuard · " + model.displayState.title)
    }
}
