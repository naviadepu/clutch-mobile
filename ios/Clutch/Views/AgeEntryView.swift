import SwiftUI
import UIKit

/// Asks for age with the dot-scale picker on a glass card, then carries
/// the answers on to the cycle questions. Only the age range is stored.
struct AgeEntryView: View {
    let signature: UIImage?

    @State private var profile = CycleProfile()
    @State private var age = 22
    @State private var goNext = false

    init(signature: UIImage? = nil) {
        self.signature = signature
    }

    private var birthYear: Int {
        Calendar.current.component(.year, from: .now) - age
    }

    var body: some View {
        OnboardingPage(title: "How old are you?", step: 2, onNext: next) {
            DotScaleCard(
                label: "Your age",
                range: 15...70,
                value: $age,
                unit: "yrs",
                trailingNote: "born \(String(birthYear))"
            )
        }
        .navigationDestination(isPresented: $goNext) {
            LastPeriodView(signature: signature, profile: $profile)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func next() {
        profile.ageRange = AgeRange(age: age)
        goNext = true
    }
}

#Preview {
    AgeEntryView()
}
