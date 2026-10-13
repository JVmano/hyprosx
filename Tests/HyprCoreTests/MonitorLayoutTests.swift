import Testing
@testable import HyprCore

@Suite struct MonitorLayoutTests {
    @Test func builtInScreenFlipsToTopLeftOrigin() {
        let infos = MonitorLayout.infos([ScreenDescription(name: "Built-in Retina Display", frame: Rect(x: 0, y: 0, width: 1512, height: 982),
                                                           visibleFrame: Rect(x: 0, y: 0, width: 1512, height: 950))])
        #expect(infos == [MonitorInfo(id: 0, name: "Built-in Retina Display", frame: Rect(x: 0, y: 0, width: 1512, height: 982),
                                      visibleFrame: Rect(x: 0, y: 32, width: 1512, height: 950))])
    }

    @Test func laptopBelowUltrawide() {
        let infos = MonitorLayout.infos([
            ScreenDescription(name: "PHL 499P9", frame: Rect(x: 0, y: 0, width: 5120, height: 1440), visibleFrame: Rect(x: 0, y: 0, width: 5120, height: 1415)),
            ScreenDescription(name: "Built-in Retina Display", frame: Rect(x: 1804, y: -982, width: 1512, height: 982),
                              visibleFrame: Rect(x: 1804, y: -982, width: 1512, height: 982)),
        ])
        #expect(infos.map(\.id) == [0, 1])
        #expect(infos[0].visibleFrame == Rect(x: 0, y: 25, width: 5120, height: 1415))
        #expect(infos[1].frame == Rect(x: 1804, y: 1440, width: 1512, height: 982))
    }

    @Test func idsFollowPositionAndRepeatedNamesGetSuffixes() {
        let infos = MonitorLayout.infos([
            ScreenDescription(name: "DELL", frame: Rect(x: 0, y: 0, width: 2560, height: 1440), visibleFrame: Rect(x: 0, y: 0, width: 2560, height: 1415)),
            ScreenDescription(name: "DELL", frame: Rect(x: 2560, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: 2560, y: 0, width: 1920, height: 1080)),
            ScreenDescription(name: "DELL", frame: Rect(x: -1920, y: 0, width: 1920, height: 1080), visibleFrame: Rect(x: -1920, y: 0, width: 1920, height: 1080)),
        ])
        #expect(infos.map(\.name) == ["DELL", "DELL (2)", "DELL (3)"])
        #expect(infos[1].frame.x == -1920)
        #expect(infos[2].frame.x == 2560)
    }

    @Test func noScreensGivesNoMonitors() {
        #expect(MonitorLayout.infos([]).isEmpty)
    }
}
