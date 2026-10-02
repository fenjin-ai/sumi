import CryptoKit
import Foundation

/// Only public material is passed as arguments; private seeds arrive on stdin.
let args = CommandLine.arguments
if args.count == 2, args[1] == "--public-key" {
    guard let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8),
          let seed = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
        fputs("Private key must be UTF-8 base64.\n", stderr)
        exit(2)
    }
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    print(privateKey.publicKey.rawRepresentation.base64EncodedString())
} else if args.count == 4 {
    guard let publicKey = Data(base64Encoded: args[1]), let signature = Data(base64Encoded: args[2]) else {
        fputs("Public key and signature must be base64.\n", stderr)
        exit(2)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    let archive = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        fputs("Update signature does not match the app's public key.\n", stderr)
        exit(1)
    }
} else {
    exit(2)
}
