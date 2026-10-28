import Foundation
import Testing
@testable import Ghostty

struct TabSidebarPaletteTests {
    @Test func palette() {
    func check(_ got: TabSidebarRGB, _ want: String, _ name: String) {
        #expect(got.hex == want.uppercased(), Comment(rawValue: name))
    }
    let dark = TabSidebarPalette(terminal: .init(hex: 0x17181A))
    let light = TabSidebarPalette(terminal: .init(hex: 0xFBFBFA))
    #expect(dark.isDark && !light.isDark, "theme detection")

    // Spec 1.3 resolved values
    check(dark.sidebar, "#1F2022", "d sidebar"); check(light.sidebar, "#F3F3F3", "l sidebar")
    check(dark.field, "#303133", "d field"); check(light.field, "#E4E4E4", "l field")
    check(dark.hover(over: dark.sidebar), "#2C2D2F", "d hover"); check(light.hover(over: light.sidebar), "#E8E8E8", "l hover")
    check(dark.pressed(over: dark.sidebar), "#343537", "d pressed"); check(light.pressed(over: light.sidebar), "#E0E0E0", "l pressed")
    check(dark.selected(over: dark.sidebar), "#393A3B", "d sel"); check(light.selected(over: light.sidebar), "#DCDCDC", "l sel")
    check(dark.selectedHover(over: dark.sidebar), "#3D3E40", "d selhover"); check(light.selectedHover(over: light.sidebar), "#D8D8D8", "l selhover")
    check(dark.selectedBorder(over: dark.sidebar), "#4A4A4C", "d selborder"); check(light.selectedBorder(over: light.sidebar), "#CACACA", "l selborder")
    check(dark.hairline, "#353638", "d hairline"); check(light.hairline, "#DBDBDB", "l hairline")
    check(dark.tile(over: dark.sidebar), "#353638", "d tile"); check(light.tile(over: light.sidebar), "#E1E1E1", "l tile")
    check(dark.text, "#EDEDED", "d text"); check(light.text, "#1D1D1D", "l text")
    check(dark.text2, "#C5C5C6", "d text2"); check(light.text2, "#535353", "l text2")
    check(dark.text3, "#A1A1A2", "d text3"); check(light.text3, "#5C5C5C", "l text3")
    check(dark.glyph, "#CECECE", "d glyph"); check(light.glyph, "#494949", "l glyph")
    check(dark.claudeTile(over: dark.sidebar), "#44312D", "d claude tile"); check(light.claudeTile(over: light.sidebar), "#ECDED9", "l claude tile")
    check(dark.popover, "#2F3032", "d popover"); check(light.popover, "#FFFFFE", "l popover")
    check(dark.popoverBorder, "#48494B", "d pop border"); check(light.popoverBorder, "#DBDBDA", "l pop border")
    check(dark.popoverHover, "#3E3E40", "d pop hover"); check(light.popoverHover, "#F2F2F1", "l pop hover")
    check(dark.popoverText, "#EEEEEF", "d pop text"); check(light.popoverText, "#1F1F1E", "l pop text")
    check(dark.popoverText2, "#B4B4B5", "d pop text2"); check(light.popoverText2, "#616161", "l pop text2")
    check(dark.popoverText3, "#828384", "d pop text3"); check(light.popoverText3, "#A6A6A5", "l pop text3")
    check(dark.segmentedTrack, "#404142", "d seg track"); check(light.segmentedTrack, "#EBEBEA", "l seg track")
    check(dark.segmentedSelected, "#505153", "d seg sel"); check(light.segmentedSelected, "#FFFFFF", "l seg sel")
    check(dark.focusHalo(), "#164D85", "d halo"); check(light.focusHalo(), "#92C3F8", "l halo")
    check(dark.settleFlash(), "#1A3653", "d flash"); check(light.settleFlash(), "#C7DDF5", "l flash")

    // Spec 1.5 group palette (dark and light): tint, border, tile, hover, sel, sel border, count pill, into
    let darkRows: [(TabSidebarGroupColor, [String])] = [
        (.red, ["#3C292A","#6B3937","#623635","#483637","#524242","#615252","#4C3A3B","#443233"]),
        (.orange, ["#3C3125","#6B4C2A","#624629","#483D32","#52493E","#61584E","#4C4136","#44392E"]),
        (.yellow, ["#3C381F","#6B5E1A","#62571B","#48442C","#524F39","#615E4A","#4C4831","#444028"]),
        (.green, ["#213827","#255E30","#25572E","#2E4434","#3B4F40","#4B5E50","#334838","#2A4030"]),
        (.blue, ["#23303F","#2A4A6D","#294564","#303C4B","#3C4855","#4D5763","#35414E","#2C3847"]),
        (.purple, ["#372E3F","#5F466D","#574164","#433B4B","#4E4655","#5D5663","#473F4E","#3F3647"]),
    ]
    let lightRows: [(TabSidebarGroupColor, [String])] = [
        (.red, ["#F0DBDD","#EAA5AC","#EDBEC2","#E5D1D3","#D9C6C8","#C7B6B7","#DDC9CB","#E6D2D4"]),
        (.orange, ["#EFE0DB","#E6B6A5","#EAC9BE","#E4D6D1","#D8CBC6","#C6BAB6","#DCCEC9","#E5D7D2"]),
        (.yellow, ["#EAE5DB","#D5C5A5","#DED3BE","#DFDBD1","#D4CFC6","#C2BEB6","#D7D3C9","#E1DCD2"]),
        (.green, ["#DEE7E0","#AFCCB6","#C4D8C9","#D4DDD6","#C9D1CB","#B8C0BA","#CCD5CE","#D5DED7"]),
        (.blue, ["#DBE1F1","#A5BAEC","#BECCEE","#D1D7E6","#C6CCDA","#B6BBC8","#C9CFDE","#D2D8E7"]),
        (.purple, ["#E8E2EC","#D1BBDC","#DCCDE3","#DED8E1","#D2CDD6","#C1BCC4","#D5D0D9","#DFD9E3"]),
    ]
    // Part D: a group with no color is neutral, ink +6% fill and +14% border.
    for pal in [dark, light] {
        check(pal.groupTint(.none), TabSidebarRGB.mix(pal.sidebar, pal.ink, 0.06).hex, "neutral tint")
        check(pal.groupBorder(.none), TabSidebarRGB.mix(pal.sidebar, pal.ink, 0.14).hex, "neutral border")
    }
    for (name, pal, rows) in [("dark", dark, darkRows), ("light", light, lightRows)] {
        for (color, want) in rows {
            let tint = pal.groupTint(color)
            let got = [tint, pal.groupBorder(color), pal.groupTile(color), pal.hover(over: tint), pal.selected(over: tint),
                       pal.selectedBorder(over: tint), pal.groupCountPill(color), pal.groupIntoFill(color)]
            let labels = ["tint","border","tile","hover","sel","selBorder","count","into"]
            for i in 0..<8 { check(got[i], want[i], "\(name) \(color) \(labels[i])") }
        }
    }
    }
}
