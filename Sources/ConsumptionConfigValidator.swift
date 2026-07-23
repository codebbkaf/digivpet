import Foundation

/// One thing wrong with the consumption config (US-170).
///
/// In the shape of `MapValidationError`: these are SEMANTIC errors, caught after the file decodes.
/// A config that will not decode never reaches here — `ConsumptionConfig.bundled` traps at launch,
/// and under `xcodebuild test` the app is the TEST_HOST, so the runner dies before a test reports.
///
/// Every rule guards a failure that is SILENT at runtime rather than a crash: a non-positive rate
/// divides by zero or makes an action free; a negative cap lets a dash bar draw backwards; an empty
/// stat table leaves every Digimon with 0 HP and no fight at all. None throws, so none would be
/// found without this.
enum ConsumptionValidationError: Error, Equatable, CustomStringConvertible {
    /// A conversion rate or coefficient that is zero or below — see `ConsumptionConfig.rates`.
    case nonPositiveRate(field: String, value: Double)

    /// A cap or amount below zero — see `ConsumptionConfig.caps`.
    case negativeMax(field: String, value: Int)

    /// No per-stage stats at all, so no Digimon has base HP, Attack or Agility to fight with.
    case emptyStatTable

    var description: String {
        switch self {
        case let .nonPositiveRate(field, value):
            return "consumption: rate '\(field)' is \(value), must be > 0"
        case let .negativeMax(field, value):
            return "consumption: cap '\(field)' is \(value), must be >= 0"
        case .emptyStatTable:
            return "consumption: stageStats is empty — no Digimon has any battle stats"
        }
    }
}

extension ConsumptionConfig {
    /// Every error in the config, or empty if it is sound.
    ///
    /// Returns ALL errors rather than throwing on the first, like `MapCatalog.validate`: the errors
    /// are independent, and an author fixing them one test run at a time is miserable.
    func validate() -> [ConsumptionValidationError] {
        var errors: [ConsumptionValidationError] = []

        for rate in rates where rate.value <= 0 {
            errors.append(.nonPositiveRate(field: rate.name, value: rate.value))
        }
        for cap in caps where cap.value < 0 {
            errors.append(.negativeMax(field: cap.name, value: cap.value))
        }
        if stageStats.isEmpty {
            errors.append(.emptyStatTable)
        }

        return errors
    }
}
