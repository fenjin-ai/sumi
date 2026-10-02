import CryptoKit
import Foundation

// Only public material is passed as arguments; private seeds arrive on stdin.
let args = CommandLine.arguments
if args.count == 2 && args[1] == "--public-key" {
    let encoded = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: encoded)!)
    print(privateKey.publicKey.rawRepresentation.base64EncodedString())
} else if args.count == 4 {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: args[1])!)
    let signature = Data(base64Encoded: args[2])!
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        fputs("Update signature does not match the app's public key.\n", stderr)
        exit(1)
    }
} else {
    exit(2)
}
