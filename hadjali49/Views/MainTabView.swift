import SwiftUI

public struct MainTabView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var selectedTab: Int = 0

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                DownloadsView()
            }
            .tabItem {
                Label("التنزيلات", systemImage: "bolt.fill")
            }
            .tag(0)

            NavigationView {
                SocialMP3View()
            }
            .tabItem {
                Label("Social & MP3", systemImage: "music.note.tv.fill")
            }
            .tag(1)

            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("الإعدادات", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
        .environmentObject(downloadManager)
        .accentColor(Color(red: 6/255, green: 182/255, blue: 212/255))
    }
}

public struct SettingsView: View {
    @AppStorage("concurrentSegments") private var concurrentSegments: Double = 8
    @AppStorage("autoPlayAfterDownload") private var autoPlayAfterDownload: Bool = true

    public var body: some View {
        ZStack {
            Color(red: 15/255, green: 23/255, blue: 42/255).ignoresSafeArea()

            Form {
                Section(header: Text("إعدادات محرك التحميل التوربو").foregroundColor(.cyan)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("عدد المسارات المتزامنة:")
                            Spacer()
                            Text("\(Int(concurrentSegments)) مسار")
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                        }
                        Slider(value: $concurrentSegments, in: 1...16, step: 1)
                            .accentColor(.cyan)
                    }
                    .listRowBackground(Color(red: 30/255, green: 41/255, blue: 59/255))

                    Toggle("التشغيل التلقائي بعد انتهاء التحميل", isOn: $autoPlayAfterDownload)
                        .listRowBackground(Color(red: 30/255, green: 41/255, blue: 59/255))
                }

                Section(header: Text("مكان حفظ الملفات (iPhone)").foregroundColor(.cyan)) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("تطبيق الملفات (Files App)")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("On My iPhone ▸ hadjali49")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    }
                    .listRowBackground(Color(red: 30/255, green: 41/255, blue: 59/255))
                }

                Section(header: Text("حول التطبيق").foregroundColor(.cyan)) {
                    HStack {
                        Text("الإصدار")
                        Spacer()
                        Text("v2.2.0 (iOS Native)")
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color(red: 30/255, green: 41/255, blue: 59/255))

                    HStack {
                        Text("المطور")
                        Spacer()
                        Text("hadjali49 Studio")
                            .foregroundColor(.cyan)
                    }
                    .listRowBackground(Color(red: 30/255, green: 41/255, blue: 59/255))
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("الإعدادات (Settings)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
