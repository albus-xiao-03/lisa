// Test-only. Builds the JSON text a scripted model answers with, in the structured-output shape the extraction
// pipeline requests (MODEL-02). Used by the model-driven integration suites (L09, L10, L19).

import Foundation
import LisaInference

/// Scripted model replies.
enum ModelReplies {
    /// `{"items": [...]}` holding `items`, as a model would answer.
    static func items(_ items: ModelExtractedItem...) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ModelExtractionPayload(items: items)) else { return "{\"items\": []}" }
        return String(decoding: data, as: UTF8.self)
    }
}
