import Foundation

/// Region-aware poison-control guidance.
/// Covers CA, US, GB with correct numbers; falls back to generic text for all others.
struct PoisonControl {
    let text: String
    /// tel: URL to dial directly; nil when no single number applies (generic fallback).
    let phoneURL: URL?

    static func info(for region: Locale.Region?) -> PoisonControl {
        switch region?.identifier {
        case "CA":
            return PoisonControl(
                text: "Poison Centre: 1-844-764-7669 (Quebec: 1-800-463-5060)",
                phoneURL: URL(string: "tel:18447647669")
            )
        case "US":
            return PoisonControl(
                text: "Poison Control: 1-800-222-1222",
                phoneURL: URL(string: "tel:18002221222")
            )
        case "GB":
            return PoisonControl(
                text: "Call NHS 111 for advice, or 999 in an emergency",
                phoneURL: URL(string: "tel:111")
            )
        default:
            return PoisonControl(
                text: "Contact your local poison control centre immediately",
                phoneURL: nil
            )
        }
    }
}
