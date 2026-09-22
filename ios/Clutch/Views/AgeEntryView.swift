import SwiftUI
import UIKit

/// Third screen: asks for age with the dot-scale picker on a glass card,
/// then carries the answers on to the cycle questions.
struct AgeEntryView: View {
    let signature: UIImage?

    @State private var profile = CycleProfile()
    @State private var goNext = false

    init(signature: UIImage? = nil) {
        self.signature = signature
    }

    private var birthYear: Int {
        Calendar.current.component(.year, from: .now) - profile.age
    }

    var body: some View {
        OnboardingPage(title: "How old are you?", step: 1, onNext: { goNext = true }) {
            DotScaleCard(
                label: "Your age",
                range: 13...70,
                value: $profile.age,
                unit: "yrs",
                trailingNote: "born \(String(birthYear))"
            )
        }
        .navigationDestination(isPresented: $goNext) {
            LastPeriodView(signature: signature, profile: $profile)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    AgeEntryView()
}
