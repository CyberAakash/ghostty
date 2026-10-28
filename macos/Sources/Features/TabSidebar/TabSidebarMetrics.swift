import CoreGraphics

/// Every measurement of the sidebar, in points. The numbers come from the design spec (Claude
/// Design project "Vertical Tab Sidebar UX Design", spec part 1, section 2); keep them in sync
/// with it rather than adjusting values here by eye.
enum TabSidebarMetrics {
    // MARK: Sidebar and control bar
    static let minWidth: CGFloat = 180
    static let defaultWidth: CGFloat = 260
    static let maxWidth: CGFloat = 420
    static let resizeHandleWidth: CGFloat = 6
    static let edgeStripWidth: CGFloat = 6
    static let hairline: CGFloat = 1

    static let controlBarHeight: CGFloat = 40
    static let controlBarPadding: CGFloat = 8
    static let controlBarGap: CGFloat = 4
    static let searchHeight: CGFloat = 26
    static let searchRadius: CGFloat = 6
    static let searchPaddingLeading: CGFloat = 8
    static let searchPaddingTrailing: CGFloat = 4
    static let searchInnerGap: CGFloat = 6
    static let searchIcon: CGFloat = 12
    static let searchFont: CGFloat = 12
    static let shortcutHintFont: CGFloat = 11
    /// The "⇧⌘A" hint is hidden below this sidebar width.
    static let shortcutHintMinWidth: CGFloat = 240
    static let clearButton: CGFloat = 18
    static let focusStroke: CGFloat = 1
    static let focusHalo: CGFloat = 2
    static let toolbarButton: CGFloat = 26
    static let toolbarButtonRadius: CGFloat = 6
    static let toolbarIcon: CGFloat = 14
    // Custom top bar (design: Part C)
    static let topBarButton: CGFloat = 28
    static let topBarToggleX: CGFloat = 78
    static let topBarPadding: CGFloat = 14

    // MARK: List
    static let listPaddingTop: CGFloat = 6
    static let listPaddingHorizontal: CGFloat = 6
    static let listTailMinHeight: CGFloat = 48
    static let blockGap: CGFloat = 2
    static let sectionHeaderHeight: CGFloat = 22
    static let sectionHeaderPaddingHorizontal: CGFloat = 8
    static let sectionHeaderGap: CGFloat = 5
    static let sectionPinIcon: CGFloat = 10
    static let sectionFont: CGFloat = 10
    static let sectionTracking: CGFloat = 0.6
    static let pinnedSeparatorMargin: CGFloat = 6
    static let pinnedContainerPadding: CGFloat = 4
    static let blockDividerInset: CGFloat = 2
    static let blockDividerMargin: CGFloat = 4
    static let tabHeaderHeight: CGFloat = 24
    static let tabHeaderPaddingLeading: CGFloat = 4
    static let tabHeaderPaddingTrailing: CGFloat = 2
    static let tabHeaderGap: CGFloat = 6
    static let tabHeaderMarginTop: CGFloat = 4
    /// A multi-pane tab: its panes sit 16 pt in, under a 1 pt guide line at x = 10.
    static let paneIndent: CGFloat = 16
    static let paneGuideX: CGFloat = 10
    static let multiPaneMargin: CGFloat = 6
    static let tabHeaderIcon: CGFloat = 12
    static let tabHeaderChevronBox: CGFloat = 12
    static let tabCountFont: CGFloat = 10
    static let tabCountPadding: CGFloat = 5
    static let tabCountRadius: CGFloat = 7
    static let sectionChevronBox: CGFloat = 12
    static let sectionHeaderRadius: CGFloat = 6
    static let headerButton: CGFloat = 20
    static let headerButtonRadius: CGFloat = 5
    static let headerButtonIcon: CGFloat = 12

    // MARK: Groups
    static let groupRadius: CGFloat = 8
    static let groupBorder: CGFloat = 1
    static let groupMarginVertical: CGFloat = 6
    static let groupPaddingTrailing: CGFloat = 4
    static let groupRail: CGFloat = 3
    static let groupPaddingLeading: CGFloat = 7
    static let groupHeaderHeight: CGFloat = 28
    static let groupHeaderPaddingHorizontal: CGFloat = 2
    static let groupHeaderGap: CGFloat = 6
    static let groupHeaderRadius: CGFloat = 6
    static let groupHeaderFont: CGFloat = 12
    static let chevronBox: CGFloat = 16
    static let chevronHitWidth: CGFloat = 24
    static let groupHeaderIcon: CGFloat = 12
    static let chevronRadius: CGFloat = 4
    static let chevronGlyph: CGFloat = 10
    static let groupDot: CGFloat = 8
    static let countFont: CGFloat = 11
    static let countPaddingHorizontal: CGFloat = 6
    static let countRadius: CGFloat = 8
    static let collapsedIndicatorGap: CGFloat = 4
    static let collapsedBadge: CGFloat = 10
    static let collapsedDot: CGFloat = 10
    static let collapsedDotOverlap: CGFloat = 4
    static let collapsedDotLimit = 5
    static let collapsedBell: CGFloat = 10
    static let collapsedUnreadDot: CGFloat = 7
    static let groupBodyGap: CGFloat = 2
    static let groupBottomStrip: CGFloat = 4

    // MARK: Rows
    static let rowPaddingVertical: CGFloat = 5
    static let rowPaddingHorizontal: CGFloat = 8
    static let rowRadius: CGFloat = 6
    static let rowIconGap: CGFloat = 8
    static let rowMinHeightOneLine: CGFloat = 28
    static let rowMinHeightTwoLines: CGFloat = 42
    static let tile: CGFloat = 22
    // Relaxed density (design: Part A, density)
    static let relaxedMinHeight: CGFloat = 44
    static let relaxedMinHeightTwoLines: CGFloat = 56
    static let relaxedPaddingVertical: CGFloat = 6
    static let relaxedPaddingHorizontal: CGFloat = 12
    static let relaxedTile: CGFloat = 26
    static let relaxedTitleFont: CGFloat = 13
    /// Extra space above and below each row so rows sit 6 pt apart (blockGap 2 + 2 + 2).
    static let relaxedRowMargin: CGFloat = 2
    static let branchChipMaxWidth: CGFloat = 96
    static let tileRadius: CGFloat = 6
    static let tileGlyph: CGFloat = 14
    static let statusBadge: CGFloat = 12
    static let statusBadgeOffset: CGFloat = -4
    static let statusBadgeRing: CGFloat = 1.5
    static let statusBadgeGlyph: CGFloat = 8
    static let titleFont: CGFloat = 12
    static let titleLine: CGFloat = 16
    static let subtitleFont: CGFloat = 11
    static let subtitleLine: CGFloat = 14
    static let subtitleIcon: CGFloat = 10
    static let subtitleIconGap: CGFloat = 4
    static let subtitleGapAbove: CGFloat = 2
    static let diffFont: CGFloat = 10
    static let diffPaddingHorizontal: CGFloat = 5
    static let diffRadius: CGFloat = 4
    static let diffGap: CGFloat = 4
    static let summaryFont: CGFloat = 11
    static let summaryGlyph: CGFloat = 11
    static let summaryGlyphSlot: CGFloat = 12
    static let summaryGap: CGFloat = 6
    static let summaryBadge: CGFloat = 10
    static let moreLeading: CGFloat = 18
    static let trailingIndicatorGap: CGFloat = 4
    static let trailingBell: CGFloat = 12
    static let unreadDot: CGFloat = 7
    static let selectedBorder: CGFloat = 1
    static let keyboardFocusRing: CGFloat = 2
    static let highlightRadius: CGFloat = 2
    static let renameHeight: CGFloat = 20
    static let renamePaddingHorizontal: CGFloat = 5
    static let renameRadius: CGFloat = 4

    // MARK: Hover pill
    static let pillTop: CGFloat = 3
    static let pillTrailing: CGFloat = 4
    static let pillTopRelaxed: CGFloat = 6
    static let pillTrailingRelaxed: CGFloat = 6
    static let pillHeight: CGFloat = 22
    static let pillRadius: CGFloat = 6
    static let pillPadding: CGFloat = 1
    static let pillButton: CGFloat = 20
    static let pillButtonRadius: CGFloat = 5
    // Controls drawn on each terminal pane (design: Part D, RD4)
    static let paneControlTop: CGFloat = 6
    static let paneControlTopMaximized: CGFloat = 30
    static let paneControlTrailing: CGFloat = 8
    static let pillIcon: CGFloat = 12

    // MARK: Details card
    static let cardWidth: CGFloat = 288
    static let cardPadding: CGFloat = 12
    static let cardRadius: CGFloat = 10
    static let cardLineGap: CGFloat = 6
    static let cardOffsetX: CGFloat = 8
    static let cardWindowMargin: CGFloat = 8
    static let cardTitleFont: CGFloat = 12
    static let cardPathFont: CGFloat = 11
    static let cardInfoFont: CGFloat = 11
    static let cardInfoIcon: CGFloat = 12

    // MARK: Menus (swatch row is a custom view inside an NSMenu)
    static let swatch: CGFloat = 18
    static let swatchGap: CGFloat = 8
    static let swatchHoverScale: CGFloat = 1.08
    static let swatchPressedScale: CGFloat = 0.92
    static let swatchRing: CGFloat = 2
    static let swatchRingGap: CGFloat = 2
    static let swatchPadding = (top: CGFloat(8), leading: CGFloat(14), bottom: CGFloat(8), trailing: CGFloat(14))

    // MARK: View-options popover
    static let optionsWidth: CGFloat = 252
    static let optionsPadding: CGFloat = 12
    static let optionsGap: CGFloat = 12
    static let optionsRadius: CGFloat = 10
    static let optionsAnchorInset: CGFloat = 8
    static let optionsAnchorGap: CGFloat = 6
    static let optionsLabelFont: CGFloat = 11
    static let segmentedHeight: CGFloat = 24
    static let segmentedPadding: CGFloat = 2
    static let segmentedGap: CGFloat = 2
    static let segmentedRadius: CGFloat = 6
    static let segmentRadius: CGFloat = 4.5
    static let segmentFont: CGFloat = 12
    static let checkRowHeight: CGFloat = 22
    static let checkRowPadding: CGFloat = 6
    static let checkRowGap: CGFloat = 6
    static let checkRowRadius: CGFloat = 4
    static let checkRowFont: CGFloat = 13

    // MARK: Drag and drop
    static let dropLine: CGFloat = 2
    static let dropLineInset: CGFloat = 2
    static let dropDot: CGFloat = 8
    static let pinZoneHeight: CGFloat = 32
    static let ghostHeight: CGFloat = 32
    static let ghostMaxWidth: CGFloat = 260
    static let sourceOpacity: Double = 0.35
    static let dragThreshold: CGFloat = 4
    static let headerTopStrip: CGFloat = 8
    static let autoScrollBand: CGFloat = 32
    static let cancelDistance: CGFloat = 24

    // MARK: Empty state
    static let emptyIllustration: CGFloat = 48
}
