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

/// Lightweight fingerprint generator that creates a hash based on only the appended content
/// (without any context variables like ENVs or current commit sha). It is used in cases when
/// full context is not required (e.g. generating -Swift.h override)
class ContextAgnosticFingerprintGeneratorFactory {
    private let fileReader: FileReader
    private let algorithm: HashingAlgorithm = MD5Algorithm()

    init(fileReader: FileReader) {
        self.fileReader = fileReader
    }

    /// Builds the default fingerprint generator that uses md5 as a hashing algorithm
    func build() -> FingerprintGenerator {
        let accumulator = FingerprintAccumulatorImpl(algorithm: algorithm, fileReader: fileReader)
        return FingerprintGenerator(envFingerprint: "", accumulator, algorithm: algorithm)
    }
}
