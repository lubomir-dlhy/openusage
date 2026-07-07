import XCTest
@testable import OpenUsage

/// Compact must be tighter than Default on every *spacing* dimension — the setting's whole point. A
/// tweak that accidentally inverts or equalizes a pair would make Density "do nothing" again without
/// any compile error. `meterHeight` is the deliberate exception: Compact's one/two-line meter row
/// gives the progress bar its own full width, so the bar is intentionally *taller* (more prominent),
/// asserted separately below.
final class DensitySettingTests: XCTestCase {
    func testCompactIsTighterOnEveryDimension() {
        let spacing: [(String, KeyPath<DensitySetting, CGFloat>)] = [
            ("barRowPadding", \.barRowPadding),
            ("textRowPadding", \.textRowPadding),
            ("condensedTextRowTopPadding", \.condensedTextRowTopPadding),
            ("rowInnerSpacing", \.rowInnerSpacing),
            ("sectionSpacing", \.sectionSpacing),
            ("headerToCardSpacing", \.headerToCardSpacing),
            ("cardGutter", \.cardGutter),
            ("controlRowPadding", \.controlRowPadding),
            ("contentTopPadding", \.contentTopPadding),
            ("estimatedMetricRowHeight", \.estimatedMetricRowHeight),
        ]
        for (name, dimension) in spacing {
            XCTAssertLessThan(
                DensitySetting.compact[keyPath: dimension],
                DensitySetting.regular[keyPath: dimension],
                "\(name) should be tighter in Compact"
            )
        }
    }

    func testCompactMeterBarIsMoreProminent() {
        // Compact's full-width meter deliberately makes the bar taller than Regular, not thinner.
        XCTAssertGreaterThan(DensitySetting.compact.meterHeight, DensitySetting.regular.meterHeight)
    }

    func testCompactStepsTypeDownOneSize() {
        let type: [(String, KeyPath<DensitySetting, CGFloat>)] = [
            ("labelPointSize", \.labelPointSize),
            ("supportingPointSize", \.supportingPointSize),
            ("headerPointSize", \.headerPointSize),
            ("planBadgePointSize", \.planBadgePointSize),
        ]
        for (name, size) in type {
            XCTAssertEqual(
                DensitySetting.compact[keyPath: size],
                DensitySetting.regular[keyPath: size] - 1,
                "\(name) should be exactly one point down in Compact"
            )
        }
        XCTAssertEqual(DensitySetting.compact.headerIconSize, DensitySetting.regular.headerIconSize - 2)
    }

    func testSectionSpacingStaysWiderThanRowRhythm() {
        // Groups must still read as groups: the section gap has to clearly beat the in-card step.
        for density in DensitySetting.allCases {
            XCTAssertGreaterThan(density.sectionSpacing, density.textRowPadding)
            XCTAssertGreaterThan(density.sectionSpacing, density.headerToCardSpacing)
        }
    }
}
