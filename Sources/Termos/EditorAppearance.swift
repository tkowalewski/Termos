import AppKit
import CodeEditSourceEditor

/// Editor configuration and Xcode-like light and dark themes.
enum EditorAppearance {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static func configuration(for appearance: NSAppearance) -> SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(theme: theme(for: appearance), font: font, wrapLines: false),
            // Tab and automatic indentation insert spaces, also in files indented with tabs.
            behavior: .init(indentOption: .spaces(count: 2)),
            layout: .init(),
            peripherals: .init(showMinimap: false)
        )
    }

    static func theme(for appearance: NSAppearance) -> EditorTheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    }

    static let light = EditorTheme(
        text: .init(color: hex(0x1F1F24)),
        insertionPoint: hex(0x000000),
        invisibles: .init(color: hex(0xD6D6D6)),
        background: hex(0xFFFFFF),
        lineHighlight: hex(0xECF5FF),
        selection: hex(0xB2D7FF),
        keywords: .init(color: hex(0x9B2393), bold: true),
        commands: .init(color: hex(0x326D74)),
        types: .init(color: hex(0x0B4F79)),
        attributes: .init(color: hex(0x815F03)),
        variables: .init(color: hex(0x0F68A0)),
        values: .init(color: hex(0x6C36A9)),
        numbers: .init(color: hex(0x1C00CF)),
        strings: .init(color: hex(0xC41A16)),
        characters: .init(color: hex(0x1C00CF)),
        comments: .init(color: hex(0x5D6C79))
    )

    static let dark = EditorTheme(
        text: .init(color: hex(0xDFDFE0)),
        insertionPoint: hex(0xFFFFFF),
        invisibles: .init(color: hex(0x424D5B)),
        background: hex(0x1F1F24),
        lineHighlight: hex(0x23252B),
        selection: hex(0x515B70),
        keywords: .init(color: hex(0xFF7AB2), bold: true),
        commands: .init(color: hex(0x67B7A4)),
        types: .init(color: hex(0x6BDFFF)),
        attributes: .init(color: hex(0xCC9768)),
        variables: .init(color: hex(0x4EB0CC)),
        values: .init(color: hex(0xB281EB)),
        numbers: .init(color: hex(0xD9C97C)),
        strings: .init(color: hex(0xFF8170)),
        characters: .init(color: hex(0xD9C97C)),
        comments: .init(color: hex(0x7F8C98))
    )

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
