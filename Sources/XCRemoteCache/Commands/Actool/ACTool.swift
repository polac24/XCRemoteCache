// Copyright (c) 2023 Spotify AB.
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

enum ACToolResult: Equatable {
    /// the actool-generated interfaces match ones observed on a producer side
    case cacheHit(dependencies: [URL])
    /// the generated interface is different - leads to a cache miss
    case cacheMiss
}

class ACTool {
    private let markerReader: ListReader
    private let metaReader: MetaReader
    private let fingerprintAccumulator: FingerprintAccumulator
    private let metaPathProvider: MetaPathProvider

    init(
        markerReader: ListReader,
        metaReader: MetaReader,
        fingerprintAccumulator: FingerprintAccumulator,
        metaPathProvider: MetaPathProvider
    ) {
        self.markerReader = markerReader
        self.metaReader = metaReader
        self.fingerprintAccumulator = fingerprintAccumulator
        self.metaPathProvider = metaPathProvider
    }

    func run() throws -> ACToolResult {
        guard markerReader.canRead() else {
            // do nothing if the RC is disabled
            return .cacheMiss
        }
        let dependencies = try markerReader.listFilesURLs()

        // Read meta's sources files & fingerprint from the artifacts's meta
        let metaPath = try metaPathProvider.getMetaPath()
        let meta = try metaReader.read(localFile: metaPath)
        // Note that assetsSourcesFingerprint is a raw fingerprint (compares only
        // file contents, not a context like configuration or platform)
        let localFingerprint = try computeFingerprints(meta.assetsSources)
        // Disable RC if the is fingerprint doesn't match
        return (localFingerprint == meta.assetsSourcesFingerprint ? .cacheHit(dependencies: dependencies) : .cacheMiss)
    }

    private func computeFingerprints(_ paths: [String]) throws -> RawFingerprint {
        fingerprintAccumulator.reset()
        for path in paths {
            let file = URL(fileURLWithPath: path)
            do {
                try fingerprintAccumulator.append(file)
            } catch FingerprintAccumulatorError.missingFile(let content){
                errorLog("Expected assets file \(content.path) was not found after the actool step, cannot reuse the artifact")
                throw FingerprintAccumulatorError.missingFile(content)
            }
        }
        return try fingerprintAccumulator.generate()
    }
}
