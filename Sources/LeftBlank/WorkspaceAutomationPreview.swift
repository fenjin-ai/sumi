import AppKit
import CryptoKit
import Foundation
import LeftBlankAutomation
import LeftBlankCore
import PDFKit

struct AutomationCompiledPreview {
    var key: String
    var data: Data
}

extension WorkspaceAutomation {
    func handlePreview(_ operation: String, _ args: JSONValue, workspace: Workspace) async throws -> JSONValue? {
        switch operation {
        case "get_preview":
            try requireCurrent(args, workspace: workspace, revisionRequired: !args["expected_revision"].isNull)
            let diagnostics = workspace.diagnostics.prefix(50).map {
                JSONValue.object([
                    "message": .string(String($0.message.prefix(1000))), "severity": .number(Double($0.severity)),
                    "line": .number(Double($0.position.line)), "character": .number(Double($0.position.character)),
                    "uri": .string($0.url.absoluteString),
                ])
            }
            return .object([
                "document_id": .string(documentID), "revision": .string(revision(workspace)),
                "ready": .bool(workspace.serviceReady), "stale": .bool(workspace.previewStale),
                "has_successful_preview": .bool(workspace.hasSuccessfulPreview),
                "diagnostics": .array(diagnostics), "truncated": .bool(workspace.diagnostics.count > 50),
            ])
        case "render_page", "export_pdf":
            try requireEditable(workspace)
            try requireCurrent(args, workspace: workspace, revisionRequired: true)
            let expected = revision(workspace), id = documentID
            let data = try await currentPDF(workspace)
            try requireCurrent(args, workspace: workspace, revisionRequired: true)
            guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
                throw AutomationFailure("preview_unavailable", "The typesetting service did not return a readable PDF.")
            }
            var result: [String: JSONValue] = [
                "document_id": .string(id), "revision": .string(expected),
                "page_count": .number(Double(pdf.pageCount)),
            ]
            if operation == "render_page" {
                let number = args["page"].int ?? 1, width = args["width"].int ?? 800
                guard number >= 1, number <= pdf.pageCount, let page = pdf.page(at: number - 1) else {
                    throw AutomationFailure("invalid_page", "The requested page is outside the current PDF.")
                }
                guard (200 ... 1600).contains(width) else {
                    throw AutomationFailure("invalid_arguments", "width must be between 200 and 1600 pixels.")
                }
                let bounds = page.bounds(for: .mediaBox)
                let size = NSSize(width: CGFloat(width), height: CGFloat(width) * bounds.height / max(bounds.width, 1))
                let thumbnail = page.thumbnail(of: size, for: .mediaBox)
                guard let tiff = thumbnail.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]), png.count <= 4 * 1024 * 1024
                else {
                    throw AutomationFailure(
                        "preview_unavailable",
                        "The requested page image is too large or unavailable.",
                    )
                }
                result["page"] = .number(Double(number))
                result["image_png"] = .string(png.base64EncodedString())
            } else {
                let folder = exportDirectory
                guard folder.resolvingSymlinksInPath().standardizedFileURL.path == folder.standardizedFileURL.path
                else {
                    throw AutomationFailure("unsafe_resource", "The export directory must not traverse symbolic links.")
                }
                try FileManager.default.createDirectory(
                    at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700],
                )
                let destination = folder.appendingPathComponent(UUID().uuidString + ".pdf")
                try data.write(to: destination, options: .atomic)
                result["path"] = .string(destination.path)
                result["uri"] = .string(destination.absoluteString)
            }
            return .object(result)
        default: return nil
        }
    }

    private func currentPDF(_ workspace: Workspace) async throws -> Data {
        let generation = accessGeneration
        let key = try await previewKey(workspace)
        try requireAccess(generation)
        if let compiledPreview, compiledPreview.key == key {
            return compiledPreview.data
        }
        guard workspace.serviceReady, !workspace.exporting else {
            throw AutomationFailure("editor_busy", "Wait for the typesetting service or current export to finish.")
        }
        workspace.exporting = true
        defer { workspace.exporting = false }
        let data: Data
        do { (data, _) = try await workspace.compiledPDF() }
        catch { throw AutomationFailure("compilation_failed", error.localizedDescription) }
        try requireAccess(generation)
        guard try await previewKey(workspace) == key else {
            throw AutomationFailure(
                "revision_conflict",
                "The document or a project resource changed during compilation.",
            )
        }
        try requireAccess(generation)
        // Keep one modest artifact. Large books can still export without retaining another PDF in memory.
        compiledPreview = data.count <= 32 * 1024 * 1024 ? .init(key: key, data: data) : nil
        return data
    }

    private func previewKey(_ workspace: Workspace) async throws -> String {
        let root = try await workspace.library.store.compilationRoot(for: workspace.compilationURL)
        return try previewKey(workspace, root: root)
    }

    private func previewKey(_ workspace: Workspace, root: URL) throws -> String {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
        ) else {
            throw AutomationFailure("project_unavailable", "The document's project folder is unavailable.")
        }
        var files: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true || url.standardizedFileURL.path == workspace.stateDirectory
                .standardizedFileURL.path
            {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else {
                continue
            }
            // The active source is represented by the live revision, including unsaved edits.
            if url.standardizedFileURL.path == workspace.documentURL.standardizedFileURL.path {
                continue
            }
            files.append(url.path + ":" + String(values.fileSize ?? 0) + ":" +
                String(values.contentModificationDate?.timeIntervalSince1970 ?? 0))
        }
        let text = documentID + ":" + revision(workspace) + ":" + workspace.compilationURL.path +
            "\n" + files.sorted().joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
