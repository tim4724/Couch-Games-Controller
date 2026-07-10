import CryptoKit
import Foundation

/// On-demand download cache for gameplay trailers. Trailers are not bundled — they
/// would grow the install per game — so the info sheet shows cover art while the mp4
/// lands here, then plays from disk on every later open. Files live in Caches,
/// keyed by URL, so the OS reclaims them under storage pressure and a manifest URL
/// change simply fetches a new entry.
enum TrailerCache {

    private static var dir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trailers", isDirectory: true)
    }

    private static func localFile(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return dir.appendingPathComponent("\(key).mp4")
    }

    /// Local file for `url`, downloading it first if absent. Nil on any failure.
    static func fetch(_ url: URL) async -> URL? {
        let fm = FileManager.default
        let dest = localFile(for: url)
        if fm.fileExists(atPath: dest.path) { return dest }
        guard let (tmp, response) = try? await URLSession.shared.download(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            try fm.moveItem(at: tmp, to: dest)
        } catch {
            // A concurrent fetch may have landed the file first — that copy is fine.
            return fm.fileExists(atPath: dest.path) ? dest : nil
        }
        return dest
    }
}
