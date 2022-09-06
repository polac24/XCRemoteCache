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

@testable import XCRemoteCache
import XCTest

class EnvironmentFingerprintGeneratorTests: XCTestCase {

    private static let defaultENV = [
        "GCC_PREPROCESSOR_DEFINITIONS": "GCC",
        "CLANG_COVERAGE_MAPPING": "YES",
        "TARGET_NAME": "TARGET",
        "CONFIGURATION": "CONG",
        "PLATFORM_NAME": "PLAT",
        "XCODE_PRODUCT_BUILD_VERSION": "XC",
        "CURRENT_PROJECT_VERSION": "1",
        "DYLIB_COMPATIBILITY_VERSION": "2",
        "DYLIB_CURRENT_VERSION": "3",
        "PRODUCT_MODULE_NAME": "4",
        "ARCHS": "AR",
    ]
    /// Corresponds to EnvironmentFingerprintGenerator.version
    private static let currentVersion = "5"

    private var config: XCRemoteCacheConfig!
    private var generator: FingerprintAccumulator! {
        return generatorFake
    }

    private var generatorFake: FingerprintAccumulatorFake!
    private var fingerprintGenerator: EnvironmentFingerprintGenerator!

    override func setUp() {
        super.setUp()
        config = XCRemoteCacheConfig(sourceRoot: "")
        generatorFake = FingerprintAccumulatorFake(FileManagerFake())
        fingerprintGenerator = EnvironmentFingerprintGenerator(
            configuration: config,
            env: Self.defaultENV,
            generator: generator
        )
    }

    func testConsidersDefaultEnvs() throws {
        let fingerprint = try fingerprintGenerator.generateFingerprint()

        XCTAssertEqual(fingerprint, "GCC,YES,TARGET,CONG,PLAT,XC,1,2,3,4,AR,\(Self.currentVersion)")
    }

    func testFingerprintIncludesVersionAsLastComponent() throws {
        let fingerprint = try fingerprintGenerator.generateFingerprint()

        XCTAssertTrue(fingerprint.hasSuffix(",\(Self.currentVersion)"))
    }

    func testMissedEnvAppendsEmptyStringToGenerator() throws {
        let fingerprintGenerator = EnvironmentFingerprintGenerator(
            configuration: config,
            env: [:],
            generator: generator
        )

        let fingerprint = try fingerprintGenerator.generateFingerprint()

        XCTAssertEqual(fingerprint, ",,,,,,,,,,,\(Self.currentVersion)")
    }

    func testConsidersCustomEnvs() throws {
        var config = self.config!
        config.customFingerprintEnvs = ["CUSTOM_ENV"]
        var env = Self.defaultENV
        env["CUSTOM_ENV"] = "CUSTOM_VALUE"
        let fingerprintGenerator = EnvironmentFingerprintGenerator(
            configuration: config,
            env: env,
            generator: generator
        )

        let fingerprint = try fingerprintGenerator.generateFingerprint()

        XCTAssertEqual(fingerprint, "GCC,YES,TARGET,CONG,PLAT,XC,1,2,3,4,AR,CUSTOM_VALUE,\(Self.currentVersion)")
    }

    func testFingerprintIsGeneratedOnce() throws {
        let fingerprint1 = try fingerprintGenerator.generateFingerprint()
        let fingerprint2 = try fingerprintGenerator.generateFingerprint()
        XCTAssertEqual(fingerprint1, fingerprint2)
        XCTAssertEqual(generatorFake.generateCallsCount, 1)
    }
}
