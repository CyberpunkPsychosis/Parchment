import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var loc: Localization
    @State private var switchedMode = true
    @State private var clashMode = false
    @State private var slider1 = 0.7
    @State private var slider2 = 0.4

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("settings.title")).font(FlowTheme.title(30)).foregroundStyle(FlowTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        VStack(spacing: 20) {
                            Toggle(loc.t("settings.switched"), isOn: $switchedMode)
                                .toggleStyle(FlowToggleStyle())
                            Divider().overlay(FlowTheme.stroke)
                            Toggle(loc.t("settings.clash"), isOn: $clashMode)
                                .toggleStyle(FlowToggleStyle())
                            Divider().overlay(FlowTheme.stroke)
                            sliderRow(loc.t("settings.sliders"), value: $slider1)
                            sliderRow(loc.t("settings.scheme"), value: $slider2)
                            Divider().overlay(FlowTheme.stroke)
                            HStack {
                                Text(loc.t("settings.selected"))
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(FlowTheme.gray)
                            }
                            .font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                        }
                        .padding(18)
                    }

                    // Language switch (中 / 英)
                    Card {
                        HStack {
                            Text(loc.t("settings.language")).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
                            Spacer()
                            Picker("", selection: Binding(get: { loc.lang }, set: { loc.set($0) })) {
                                ForEach(Lang.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        .padding(18)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .background(PaperBackground())
    }

    private func sliderRow(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 14) {
            Text(title).font(FlowTheme.body(16)).foregroundStyle(FlowTheme.ink)
            Spacer()
            Slider(value: value).tint(FlowTheme.teal).frame(width: 150)
        }
    }
}
