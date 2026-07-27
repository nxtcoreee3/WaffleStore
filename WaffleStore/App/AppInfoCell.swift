import SwiftUI
import PartyUI

public struct AppInfoCell: View {
    public init() {}
    public var body: some View {
        HStack(spacing: 14) {
            LocalAppIconCell()
            VStack(alignment: .leading) {
                Text(AppInfo.appName)
                    .font(.system(.title3, weight: .semibold))
                Text("Version \(AppInfo.appVersion) (\(AppInfo.appBuild))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LocalAppIconCell: View {
    var image: Image
    init(image: Image = Image(uiImage: AppInfo.appIcon ?? UIImage())) {
        self.image = image
    }
    var body: some View {
        if #available(iOS 19.0, *) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .background(LocalPlaceholderAppIconCell())
                .clipShape(.rect(cornerRadius: 18))
        } else {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .background(LocalPlaceholderAppIconCell())
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1.5)
                }
        }
    }
}

struct LocalPlaceholderAppIconCell: View {
    var body: some View {
        Image(systemName: "questionmark.square")
            .foregroundStyle(.secondary)
            .frame(width: 64, height: 64)
            .background(Color(.systemGray5))
    }
}
