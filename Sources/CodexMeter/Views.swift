import AppKit
import SwiftUI

private enum MeterPalette {
    static let blue = Color(red: 0.31, green: 0.62, blue: 1.0)
    static let card = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let radius: CGFloat = 8
    static let fontSize: CGFloat = 11
}

private enum ProviderSelection: String, CaseIterable, Identifiable {
    case codex = "Codex"
    case cursor = "Cursor"
    var id: Self { self }
}

struct MenuContentView: View {
    @EnvironmentObject private var store: AccountStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedID: UUID?
    @State private var provider: ProviderSelection = .codex
    @State private var providerTransitionForward = true
    @Namespace private var providerTabAnimation
    @Namespace private var accountTabAnimation

    private var selectedProfile: AccountProfile? {
        let id = selectedID ?? store.activeID
        return store.profiles.first(where: { $0.id == id }) ?? store.profiles.first
    }

    private var selectedSnapshot: AccountSnapshot? {
        selectedProfile.flatMap { store.snapshots[$0.id] }
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                providerPicker

                Group {
                    switch provider {
                    case .codex:
                        if store.profiles.isEmpty {
                            emptyState
                        } else {
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 12) {
                                    if let profile = selectedProfile {
                                        accountPanel(profile: profile)
                                        quickStats
                                        TokenActivityCard(dailyUsage: selectedSnapshot?.dailyUsage ?? [])
                                        actions
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.bottom, 14)
                            }
                        }
                    case .cursor:
                        ScrollView(showsIndicators: false) {
                            CursorProviderView(
                                snapshot: store.cursorSnapshot,
                                error: store.cursorError,
                                isRefreshing: store.isRefreshing
                            )
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                        }
                    }
                }
                .id(provider)
                .transition(.asymmetric(
                    insertion: .move(edge: providerTransitionForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: providerTransitionForward ? .leading : .trailing).combined(with: .opacity)
                ))
            }
        }
        .font(.system(size: MeterPalette.fontSize))
        .frame(width: 410, height: 650)
        .onAppear {
            selectedID = selectedID ?? store.activeID ?? store.profiles.first?.id
            store.refreshVisibleData(showingCursor: provider == .cursor)
        }
        .onChange(of: store.activeID) { _, id in
            if selectedID == nil { selectedID = id }
        }
        .onChange(of: provider) { _, newValue in
            store.refreshVisibleData(showingCursor: newValue == .cursor)
        }
        .alert("Codex Meter", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    private var background: some View {
        (colorScheme == .dark ? Color.black : Color.white)
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 11) {
            SwitchLogo(size: 28, color: MeterPalette.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Codex Meter")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    if let fetchedAt = provider == .codex ? selectedSnapshot?.fetchedAt : store.cursorSnapshot?.fetchedAt {
                        Text("Updated \(fetchedAt, style: .relative)")
                        .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(store.isRefreshing ? "Reading usage…" : "Local account monitor")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            HStack(spacing: 3) {
                Button {
                    store.refreshAll(includeCursorActivity: provider == .cursor)
                } label: {
                    ZStack {
                        Circle().fill(.primary.opacity(0.07))
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(store.isRefreshing)
                .help("Refresh usage")
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Quit Codex Meter")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    private var providerPicker: some View {
        HStack(spacing: 0) {
            ForEach(ProviderSelection.allCases) { item in
                Button {
                    guard provider != item else { return }
                    providerTransitionForward = item == .cursor
                    withAnimation(.easeInOut(duration: 0.24)) { provider = item }
                } label: {
                    HStack(spacing: 7) {
                        if item == .codex {
                            ProviderProductIcon(product: .codex, size: 19)
                        } else {
                            ProviderProductIcon(product: .cursor, size: 19)
                        }
                        Text(item.rawValue)
                            .font(.system(size: MeterPalette.fontSize, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .foregroundStyle(provider == item ? Color.primary : Color.secondary)
                    .background {
                        if provider == item {
                            RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .matchedGeometryEffect(id: "provider-tab", in: providerTabAnimation)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var accountStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(store.profiles) { profile in
                    let isSelected = selectedProfile?.id == profile.id
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selectedID = profile.id }
                    } label: {
                        Text(shortName(profile))
                            .font(.system(size: MeterPalette.fontSize, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 96)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background {
                                UnevenRoundedRectangle(
                                    topLeadingRadius: MeterPalette.radius,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: MeterPalette.radius,
                                    style: .continuous
                                )
                                .fill(isSelected ? MeterPalette.card : Color.primary.opacity(0.045))
                                .matchedGeometryEffect(id: isSelected ? "account-tab" : profile.id.uuidString, in: accountTabAnimation)
                            }
                            .opacity(isSelected ? 1 : 0.58)
                            .offset(y: isSelected ? 1 : 0)
                    }
                    .buttonStyle(.plain)
                    .zIndex(isSelected ? 2 : 0)
                }

                Button { store.addAccount() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: MeterPalette.fontSize, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.isRefreshing)
                .help("Add account")
            }
        }
        .frame(height: 30)
    }

    private func accountPanel(profile: AccountProfile) -> some View {
        VStack(alignment: .leading, spacing: -1) {
            accountStrip.zIndex(2)
            accountHero(profile: profile)
                .id(profile.id)
                .transition(.opacity)
        }
    }

    private func accountHero(profile: AccountProfile) -> some View {
        let snapshot = selectedSnapshot
        let limits = snapshot?.rateLimits

        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.system(size: MeterPalette.fontSize, weight: .semibold))
                            .lineLimit(1)
                        Text(snapshot?.email ?? "Waiting for account details")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let plan = snapshot?.planType {
                        Text(plan.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MeterPalette.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(MeterPalette.blue.opacity(0.12), in: Capsule())
                    }
                }

                if let error = store.accountErrors[profile.id] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                QuotaRail(title: "5-hour", window: limits?.primary, tint: MeterPalette.blue)
                QuotaRail(title: "Weekly", window: limits?.secondary, tint: MeterPalette.blue.opacity(0.55))
            }

            if store.activeID != profile.id {
                Button {
                    store.switchAccount(to: profile)
                } label: {
                    Label("Use this account", systemImage: "arrow.triangle.swap")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(MeterPalette.blue, in: RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            MeterPalette.card,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: MeterPalette.radius,
                bottomTrailingRadius: MeterPalette.radius,
                topTrailingRadius: MeterPalette.radius,
                style: .continuous
            )
        )
    }

    private var quickStats: some View {
        HStack(spacing: 8) {
            StatPill(title: "Credits", value: creditLabel, symbol: "creditcard.fill", tint: MeterPalette.blue)
            StatPill(title: "Lifetime", value: tokenLabel(selectedSnapshot?.usage?.lifetimeTokens), symbol: "text.word.spacing", tint: MeterPalette.blue)
            StatPill(title: "Streak", value: streakLabel, symbol: "flame.fill", tint: MeterPalette.blue)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ActionTile(title: "Add account", symbol: "person.badge.plus") { store.addAccount() }
                ActionTile(title: "Open status", symbol: "waveform.path.ecg") {
                    NSWorkspace.shared.open(URL(string: "https://status.openai.com")!)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                Text("Credentials stay on this Mac")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            SwitchLogo(size: 48, color: MeterPalette.blue)
            Text("Connect your first account")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("Sign-in opens in your browser and stays with the official Codex CLI.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
            Button("Add account") { store.addAccount() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var creditLabel: String {
        guard let credits = selectedSnapshot?.rateLimits?.credits else { return "—" }
        if credits.unlimited { return "Unlimited" }
        return credits.balance ?? (credits.hasCredits ? "Available" : "None")
    }

    private var streakLabel: String {
        guard let days = selectedSnapshot?.usage?.currentStreakDays else { return "—" }
        return "\(days)d"
    }

    private func tokenLabel(_ count: Int?) -> String {
        count?.formatted(.number.notation(.compactName)) ?? "—"
    }

    private func shortName(_ profile: AccountProfile) -> String {
        let source = store.snapshots[profile.id]?.email ?? profile.name
        return source.split(separator: "@").first.map(String.init) ?? source
    }
}

private struct QuotaRail: View {
    let title: String
    let window: RateLimitWindow?
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text("\(window?.usedPercent ?? 0)% used")
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.075))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(max(0, min(100, window?.usedPercent ?? 0))) / 100)
                }
            }
            .frame(height: 6)
            HStack {
                Spacer()
                if let reset = window?.resetDate {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        Text("Resets \(reset, style: .relative)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Reset unavailable").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CursorProviderView: View {
    let snapshot: CursorSnapshot?
    let error: String?
    let isRefreshing: Bool

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cursor")
                                .font(.system(size: MeterPalette.fontSize, weight: .semibold))
                            Text(snapshot?.email ?? cursorStatus)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let membership = snapshot?.membershipType {
                            Text(planName(membership).uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MeterPalette.blue)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(MeterPalette.blue.opacity(0.1), in: Capsule())
                            }
                        }

                    CursorRail(title: "Auto", percent: snapshot?.autoPercentUsed, tint: MeterPalette.blue)
                    CursorRail(title: "Models", percent: snapshot?.apiPercentUsed, tint: MeterPalette.blue.opacity(0.55))
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Included usage").font(.caption).foregroundStyle(.secondary)
                        Text(includedUsage)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                    Spacer()
                    if let reset = snapshot?.billingCycleEnd {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Cycle resets").font(.caption).foregroundStyle(.secondary)
                            Text(reset, format: .dateTime.month(.abbreviated).day())
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .padding(12)
            .background(MeterPalette.card, in: RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous))

            HStack(spacing: 8) {
                StatPill(title: "Tokens", value: compact(snapshot?.totalTokens), symbol: "text.word.spacing", tint: MeterPalette.blue)
                StatPill(title: "On demand", value: money(snapshot?.onDemandUsedCents), symbol: "bolt.fill", tint: MeterPalette.blue)
                StatPill(title: "Plan left", value: "\(Int((100 - (snapshot?.planPercentUsed ?? 0)).rounded()))%", symbol: "gauge.with.dots.needle.50percent", tint: MeterPalette.blue)
            }

            TokenActivityCard(dailyUsage: snapshot?.dailyUsage ?? [])

            HStack(spacing: 8) {
                ActionTile(title: "Dashboard", symbol: "chart.bar.xaxis") {
                    NSWorkspace.shared.open(URL(string: "https://cursor.com/dashboard?tab=usage")!)
                }
                ActionTile(title: "Cursor status", symbol: "waveform.path.ecg") {
                    NSWorkspace.shared.open(URL(string: "https://status.cursor.com")!)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                Text("Reads Cursor’s session in memory · never stored")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private var cursorStatus: String {
        if let error { return error }
        return isRefreshing ? "Reading Cursor usage…" : "Open Cursor and sign in"
    }

    private var includedUsage: String {
        guard let snapshot else { return "—" }
        return "\(money(snapshot.planUsedCents)) of \(money(snapshot.planLimitCents))"
    }

    private func money(_ cents: Int?) -> String {
        guard let cents else { return "—" }
        return (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    private func compact(_ value: Int?) -> String {
        value.map { $0.formatted(.number.notation(.compactName)) } ?? "—"
    }

    private func planName(_ value: String) -> String {
        switch value.lowercased() {
        case "free_trial": return "Pro trial"
        case "pro_plus": return "Pro+"
        case "pro_student": return "Pro"
        default: return value.replacingOccurrences(of: "_", with: " ")
        }
    }
}

private struct CursorRail: View {
    let title: String
    let percent: Double?
    let tint: Color

    var body: some View {
        let used = max(0, min(100, percent ?? 0))
        VStack(spacing: 5) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text(percent == nil ? "—" : "\(Int(used.rounded()))% used")
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.075))
                    Capsule().fill(tint).frame(width: proxy.size.width * used / 100)
                }
            }
            .frame(height: 6)
        }
    }
}

private struct StatPill: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                Text(value).font(.caption.monospacedDigit().weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous))
    }
}

private enum ActivityMode: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case cumulative = "Total"
    var id: Self { self }
}

private struct TokenActivityCard: View {
    let dailyUsage: [DailyUsageBucket]
    @State private var mode: ActivityMode = .daily

    private let calendar = Calendar.autoupdatingCurrent
    private let weeks = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Token activity")
                        .font(.system(size: MeterPalette.fontSize, weight: .semibold))
                    Text(activitySubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Activity mode", selection: $mode) {
                    ForEach(ActivityMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .font(.system(size: 10, weight: .medium))
                .controlSize(.small)
                .frame(width: 155)
            }

            let values = activityValues
            let maximum = max(values.max() ?? 0, 1)
            GeometryReader { proxy in
                let spacing: CGFloat = 3
                let columns = CGFloat(weeks)
                let cellWidth = (proxy.size.width - spacing * (columns - 1)) / columns
                let rows = Array(repeating: GridItem(.fixed(8), spacing: spacing), count: 7)
                LazyHGrid(rows: rows, spacing: spacing) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(activityColor(value: value, maximum: maximum))
                            .frame(width: cellWidth, height: 8)
                            .help(value == 0 ? "No recorded activity" : "\(value.formatted()) tokens")
                    }
                }
            }
            .frame(height: 74)
            .padding(8)
            .background(MeterPalette.card, in: RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: mode)

            HStack {
                ForEach(monthLabels.indices, id: \.self) { index in
                    Text(monthLabels[index]).frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == monthLabels.count - 1 ? .trailing : .center))
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
        }
    }

    private var dates: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (0..<(weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0 - (weeks * 7 - 1), to: today) }
    }

    private var dailyValues: [Int] {
        let buckets = dailyUsage.reduce(into: [String: Int]()) { result, bucket in
            result[String(bucket.startDate.prefix(10)), default: 0] += bucket.tokens
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return dates.map { buckets[formatter.string(from: $0)] ?? 0 }
    }

    private var activityValues: [Int] {
        switch mode {
        case .daily:
            return dailyValues
        case .weekly:
            return dailyValues.indices.map { index in
                dailyValues[max(0, index - 6)...index].reduce(0, +)
            }
        case .cumulative:
            var total = 0
            return dailyValues.map { total += $0; return total }
        }
    }

    private var activitySubtitle: String {
        let recordedDays = dailyValues.filter { $0 > 0 }.count
        return recordedDays == 0 ? "Waiting for daily usage history" : "\(recordedDays) active day\(recordedDays == 1 ? "" : "s") in this view"
    }

    private var monthLabels: [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let indexes = [0, 35, 70, dates.count - 1]
        return indexes.map { formatter.string(from: dates[$0]) }
    }

    private func activityColor(value: Int, maximum: Int) -> Color {
        guard value > 0 else { return Color.primary.opacity(0.055) }
        let intensity = Double(value) / Double(maximum)
        if intensity > 0.74 { return MeterPalette.blue }
        if intensity > 0.42 { return MeterPalette.blue.opacity(0.72) }
        if intensity > 0.16 { return MeterPalette.blue.opacity(0.42) }
        return MeterPalette.blue.opacity(0.2)
    }
}

private struct ActionTile: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { ActionTileLabel(title: title, symbol: symbol) }
            .buttonStyle(.plain)
    }
}

private struct ActionTileLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: MeterPalette.radius, style: .continuous))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AccountStore
    @AppStorage("showDockIcon") private var showDockIcon = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show Dock icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, value in
                        NSApp.applicationIconImage = AppIconRenderer.make()
                        NSApp.setActivationPolicy(value ? .regular : .accessory)
                    }
            }
            Section("Codex CLI") {
                TextField("Path to codex", text: $store.customCodexPath, prompt: Text("Auto-detect"))
                Text("Auto-detects /opt/homebrew/bin/codex and /usr/local/bin/codex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("OAuth and usage requests are handled by the official Codex CLI. Codex Meter never parses auth.json; switching uses an atomic local file copy with 0600 permissions.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 330)
        .padding()
    }
}
