// Copyright (c) 2021 Spotify AB.
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

/// Builds the FingerprintGenerator based on only appended contetn (without any context variables like ENVs
/// or current commit sha)
class ContextAgnosticFingerprintGeneratorFactory {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    /// Builds the default fingerprint generator that uses md5 as a hashing algorithm
    func build() -> FingerprintGenerator {
        let accumulator = FingerprintAccumulatorImpl(algorithm: MD5Algorithm(), fileReader: fileManager)
        return FingerprintGenerator(envFingerprint: "", accumulator, algorithm: MD5Algorithm())
    }
}
