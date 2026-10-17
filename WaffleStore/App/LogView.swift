import SwiftUI
import UIKit
import Darwin

private enum DeviceLogInfo {
    static var startupLine: String {
        "[x] \(deviceIdentifier) - iOS \(UIDevice.current.systemVersion) - \(osBuild)\n[!] Logging in and Downgrading may take longer to process due to this new method. Please be patient!\n"
    }

    private static var deviceIdentifier: String {
        let environment = ProcessInfo.processInfo.environment
        let identifier = environment["SIMULATOR_MODEL_IDENTIFIER"] ?? hardwareIdentifier
        if identifier.hasPrefix("iPhone") {
            return identifier.replacingOccurrences(of: "iPhone", with: "iPhone ")
        }
        return identifier
    }

    private static var hardwareIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown device" }
        var machine = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else { return "Unknown device" }
        return String(cString: machine)
    }

    private static var osBuild: String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown build" }
        var build = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &build, &size, nil, 0) == 0 else { return "Unknown build" }
        return String(cString: build)
    }
}

struct LogView: View {
    @State var log: String = DeviceLogInfo.startupLine
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    Text(log)
                        .padding(.top)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .multilineTextAlignment(.leading)
                    Spacer()
                        .id(0)
                }
                .onAppear {
                    pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                        let data = fileHandle.availableData
                        if data.isEmpty  {
                            fileHandle.readabilityHandler = nil
                            sema.signal()
                        } else {
                            log.append(String(data: data, encoding: .utf8)!)
                            DispatchQueue.main.async {
                                proxy.scrollTo(0)
                            }
                        }
                    }
                }
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = log
                    } label: {
                        Label("Copy Logs", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
