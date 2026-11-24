// Removing a run's local data (plan §10.8 `cleanup <run-id>`): only the run's own directory in the store, after
// checking that the path really is one of this store's run directories.

import Foundation

extension VerifyRunStore {
    /// What the run created locally, relative to its directory, sorted.
    public func items(of run: VerifyRunID) -> [String] {
        let directory = directory(of: run).standardizedFileURL
        return ((FileManager.default.enumerator(atPath: directory.path)?.allObjects as? [String]) ?? []).sorted()
    }

    /// Removes the run's directory and nothing else.
    public func remove(_ run: VerifyRunID) throws(VerifyError) {
        _ = try load(run)
        let directory = directory(of: run).standardizedFileURL
        guard directory.deletingLastPathComponent().path == runsDirectory.standardizedFileURL.path,
            directory.lastPathComponent == run.text
        else { throw .store("refusing to remove \(directory.path): not a run directory of this store") }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw .store("can't remove \(directory.path): \(error)")
        }
    }
}
