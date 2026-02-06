//
//  ClawDaddyTests.swift
//  ClawDaddyTests
//
//  Created by TJ Murphy on 2/2/26.
//

import Testing
@testable import ClawDaddy
import Foundation
import Darwin

@MainActor
struct ClawDaddyTests {

    @Test @MainActor func configDiscoveryFromStateDirLoadsGatewayAndIdentity() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("clawdaddy-tests-\(UUID().uuidString)")
        let stateDir = base.appendingPathComponent(".openclaw")
        let identityDir = stateDir.appendingPathComponent("identity")
        try fm.createDirectory(at: identityDir, withIntermediateDirectories: true)

        let config = """
        {
          "gateway": {
            "port": 18789,
            "auth": {
              "mode": "token",
              "token": "test-token"
            }
          }
        }
        """
        try config.write(to: stateDir.appendingPathComponent("openclaw.json"), atomically: true, encoding: .utf8)

        let identity = """
        {
          "version": 1,
          "deviceId": "fb950f47f7000c86304b47bafb9a8382f1ecc4163ed5751868e87b2c108da571",
          "publicKeyPem": "-----BEGIN PUBLIC KEY-----\\nMCowBQYDK2VwAyEAr2rbGoL5IQjYLywUqmuItBmlmqza2Iz9rCIHUZ5yUYY=\\n-----END PUBLIC KEY-----\\n",
          "privateKeyPem": "-----BEGIN PRIVATE KEY-----\\nMC4CAQAwBQYDK2VwBCIEIHlE23036Zkl0jdDGgHqpS3VrCEClxodmcjv9F9EQyCv\\n-----END PRIVATE KEY-----\\n"
        }
        """
        try identity.write(to: identityDir.appendingPathComponent("device.json"), atomically: true, encoding: .utf8)

        try withEnv("OPENCLAW_STATE_DIR", stateDir.path) {
            try withEnv("OPENCLAW_BIN", "/nonexistent/openclaw") {
                let client = WebSocketClient()
                client.refreshConfigForTesting()

                #expect(client.discoveredWSURLForTesting?.absoluteString == "ws://127.0.0.1:18789")
                #expect(client.hasAPIKeyForTesting)
                #expect(client.discoveryDiagnosticsForTesting.contains("source=file"))
                #expect(client.identityDiagnosticsForTesting.contains("device_id="))
            }
        }

        try? fm.removeItem(at: base)
    }

    private func withEnv(_ key: String, _ value: String, _ body: () throws -> Void) throws {
        let previous = getenv(key).map { String(cString: $0) }
        setenv(key, value, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        try body()
    }

}
