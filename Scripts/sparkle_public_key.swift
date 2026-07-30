#!/usr/bin/env swift

import CryptoKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("Usage: sparkle_public_key.swift <private-key-file>\n".utf8)
    )
    exit(64)
}

let keyURL = URL(fileURLWithPath: CommandLine.arguments[1])
let encoded = try String(contentsOf: keyURL, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let secret = Data(base64Encoded: encoded) else {
    FileHandle.standardError.write(
        Data("Sparkle private key is not valid base64.\n".utf8)
    )
    exit(65)
}

let publicKey: Data
switch secret.count {
case 32:
    let privateKey = try Curve25519.Signing.PrivateKey(
        rawRepresentation: secret
    )
    publicKey = privateKey.publicKey.rawRepresentation
case 96:
    // Sparkle's legacy export format stores its 64-byte private key followed
    // by the 32-byte public key.
    publicKey = secret.suffix(32)
default:
    let message =
        "Sparkle private key must decode to 32 or 96 bytes; "
        + "\(secret.count) bytes were provided.\n"
    FileHandle.standardError.write(
        Data(message.utf8)
    )
    exit(65)
}

print(publicKey.base64EncodedString())
