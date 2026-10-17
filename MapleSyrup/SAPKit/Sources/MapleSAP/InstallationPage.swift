import Foundation

// Local presentation only. The original itms-services/HTTPS manifest flow is
// retained; displaying this page does not establish installation success.
public enum InstallationPage {
    public static func html(name: String, version: String, target: URL) throws -> String {
        guard target.scheme == "itms-services" else { throw SAPError.invalidEndpoint }
        let literal = String(data: try JSONSerialization.data(withJSONObject: target.absoluteString, options: .fragmentsAllowed), encoding: .utf8)!
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark"><title>Install app</title>
        <style>
        :root{color-scheme:light dark;--bg:#f2f2f7;--card:#fff;--text:#1c1c1e;--muted:#636366;--blue:#007aff}
        @media(prefers-color-scheme:dark){:root{--bg:#000;--card:#1c1c1e;--text:#f5f5f7;--muted:#aeaeb2;--blue:#0a84ff}}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:17px/1.5 -apple-system,BlinkMacSystemFont,sans-serif}
        main{max-width:440px;margin:0 auto;padding:32px 20px max(28px,env(safe-area-inset-bottom))}
        .card{background:var(--card);border-radius:24px;padding:28px 24px;text-align:center}
        .icon{width:64px;height:64px;margin:0 auto 20px;display:grid;place-items:center;color:var(--blue);background:color-mix(in srgb,var(--blue) 14%,transparent);border-radius:18px}
        svg{width:32px;height:32px}h1{font-size:24px;line-height:1.2;margin:0 0 8px;overflow-wrap:anywhere}
        .version{margin:0;color:var(--muted);font-size:15px}p{margin:24px 0;color:var(--muted)}
        button{width:100%;min-height:50px;border:0;border-radius:14px;background:var(--blue);color:#fff;font:600 17px -apple-system,sans-serif;cursor:pointer}
        button:focus-visible{outline:3px solid var(--text);outline-offset:4px}.note{font-size:13px;text-align:center;margin:20px 12px}
        </style></head><body><main><section class="card">
        <div class="icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12m-5-5 5 5 5-5M4 16v4h16v-4"/></svg></div>
        <h1>\(escape(name))</h1><div class="version">Version \(escape(version))</div>
        <p>Confirm the installation prompt from iOS. Keep this screen open while the app installs.</p>
        <button id="install" type="button">Install app</button></section>
        <p class="note">If no prompt appears, tap Install app again. The IPA remains in Downloads.</p>
        </main><script>const target=\(literal);document.getElementById('install').onclick=()=>location.href=target;location.href=target;</script></body></html>
        """
    }
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
