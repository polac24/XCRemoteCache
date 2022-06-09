// Copyright (c) 2022 Spotify AB.
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import Foundation

/// Processes downloaded artifact by replacing generic paths in generated ObjC headers placed in ./include
/// and  creating an override file with an fingerprint of the generic content
class ObjCHeaderArtifactProcessor: ArtifactProcessor {
    /// All directories in an artifact that should be processed by path remapping
    private static let remappingDirs = ["include"]

    private let overrideExtension: String
    private let fileRemapper: FileDependenciesRemapper
    private let dirScanner: DirScanner
    private let fileWriter: FileWriter
    private let fingerprintGeneratorFactory: () -> FingerprintGenerator

    init(
        overrideExtension: String,
        fileRemapper: FileDependenciesRemapper,
        dirScanner: DirScanner,
        fileWriter: FileWriter,
        fingerprintGeneratorFactory: @escaping () -> FingerprintGenerator
    ) {
        self.overrideExtension = overrideExtension
        self.fileRemapper = fileRemapper
        self.dirScanner = dirScanner
        self.fileWriter = fileWriter
        self.fingerprintGeneratorFactory = fingerprintGeneratorFactory
    }

    private func findProcessingEligableFiles(path: String) throws -> [URL] {
        let remappingURL = URL(fileURLWithPath: path)
        let allFiles = try dirScanner.recursiveItems(at: remappingURL)
        return allFiles.filter({ !$0.isHidden })
    }

    /// Replaces all generic paths in a raw artifact's `include` dir with
    /// absolute paths, specific for a given machine and configuration
    /// - Parameter rawArtifact: raw artifact location
    func process(rawArtifact url: URL) throws {
        for remappingDir in Self.remappingDirs {
            let remappingPath = url.appendingPathComponent(remappingDir).path
            let allFiles = try findProcessingEligableFiles(path: remappingPath)
            for file in allFiles {
                // first create an override file that hashes the generic content of a file (before remapping)
                try generateOverride(genericFile: file)
                try allFiles.forEach(fileRemapper.remap(fromGeneric:))
            }
        }
    }

    func process(localArtifact url: URL) throws {
        for remappingDir in Self.remappingDirs {
            let remappingPath = url.appendingPathComponent(remappingDir).path
            let allFiles = try findProcessingEligableFiles(path: remappingPath)
            for file in allFiles {
                try fileRemapper.remap(fromLocal: file)
                // create an override file from the generic content of a file (after remapping)
                try generateOverride(genericFile: file)
            }
        }
    }

    private func generateOverride(genericFile: URL) throws {
        let fingerprintGenerator = fingerprintGeneratorFactory()
        try fingerprintGenerator.append(genericFile)
        let fingerprint: RawFingerprint = try fingerprintGenerator.generate()
        let fingerprintData = fingerprint.data(using: .utf8)
        let fileOverrideURL = genericFile.appendingPathExtension(overrideExtension)
        try fileWriter.write(toPath: fileOverrideURL.path, contents: fingerprintData)
    }
}

fileprivate extension URL {
    // Recognize hidden files starting with a dot
    var isHidden: Bool {
        lastPathComponent.hasPrefix(".")
    }
}
