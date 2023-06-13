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

@testable import XCRemoteCache
import XCTest

class ArtifactMetaPathProviderTests: XCTestCase {
    private let artifactURL: URL = "/artifact/"
    private let dirScannerFake = FileAccessorFake(mode: .normal)


    func testFindsExistingMeta() throws {
        let provider = ArtifactMetaPathProvider(
            artifactLocation: artifactURL,
            dirScanner: dirScannerFake
        )
        try dirScannerFake.write(toPath: "/artifact/abc.json", contents: nil)

        XCTAssertEqual(try provider.getMetaPath(), "/artifact/abc.json")
    }

    func testThrowsWhenNoJsonFileInTheArtifact() throws {
        let provider = ArtifactMetaPathProvider(
            artifactLocation: artifactURL,
            dirScanner: dirScannerFake
        )

        XCTAssertThrowsError(try provider.getMetaPath()) { error in
            switch error {
            case MetaPathProviderError.failed: break
            default:
                XCTFail("Not expected error")
            }
        }
    }

    func testDoesntSearchMetaInRecursiveDirs() throws {
        let provider = ArtifactMetaPathProvider(
            artifactLocation: artifactURL,
            dirScanner: dirScannerFake
        )
        try dirScannerFake.write(toPath: "/artifact/nested/abc.json", contents: nil)

        XCTAssertThrowsError(try provider.getMetaPath()) { error in
            switch error {
            case MetaPathProviderError.failed: break
            default:
                XCTFail("Not expected error")
            }
        }
    }
}
