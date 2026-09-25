import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Payload accepted by the input window's drop zone.
public enum DroppedInput: Transferable, Sendable {
    case imageData(Data)
    case text(String)

    public static var transferRepresentation: some TransferRepresentation {
        // Image files from Finder or a screenshot thumbnail: the system hands over a readable copy.
        FileRepresentation(importedContentType: .image) { received in
            DroppedInput.imageData(try Data(contentsOf: received.file))
        }
        // Image data dragged from another app (a browser, Preview).
        DataRepresentation(importedContentType: .image) { data in
            DroppedInput.imageData(data)
        }
        ProxyRepresentation(importing: { (text: String) in
            DroppedInput.text(text)
        })
    }
}
