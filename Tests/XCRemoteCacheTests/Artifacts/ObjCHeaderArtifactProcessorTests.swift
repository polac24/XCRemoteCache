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

@testable import XCRemoteCache

import XCTest

class ObjCHeaderArtifactProcessorTests: FileXCTestCase {

    private let fileAccessor = FileAccessorFake(mode: .strict)
    private let remapper = StringDependenciesRemapper(mappings: [.init(generic: "$(SRCROOT)", local: "/local")])
    private var fileRemapper: FileDependenciesRemapper!
    private var processor: ObjCHeaderArtifactProcessor!
    // md5 hash of "Some $(SRCROOT)"
    private let someSrcRootMd5Data = "55654c89b180824387beb8a9794264bf".data(using: .utf8)

    override func setUp() {
        super.setUp()
        fileRemapper = TextFileDependenciesRemapper(remapper: remapper, fileAccessor: fileAccessor)

        let fingerprintGenerator = ContextAgnosticFingerprintGeneratorFactory(fileReader: fileAccessor)
        processor = ObjCHeaderArtifactProcessor(
            overrideExtension: "md5",
            fileRemapper: fileRemapper,
            dirScanner: fileAccessor,
            fileWriter: fileAccessor,
            fingerprintGeneratorFactory: fingerprintGenerator.build
        )
    }

    func testProcessingRawArtifactReplacesPlaceholders() throws {
        try fileAccessor.write(toPath: "/artifact/include/file", contents: "Some $(SRCROOT)")

        try processor.process(rawArtifact: "/artifact")

        XCTAssertEqual(try fileAccessor.contents(atPath: "/artifact/include/file"), "Some /local")
    }

    func testProcessingRawArtifactReplacesInNestedInclude() throws {
        try fileAccessor.write(toPath: "/artifact/include/nested/file", contents: "Some $(SRCROOT)")

        try processor.process(rawArtifact: "/artifact")

        XCTAssertEqual(try fileAccessor.contents(atPath: "/artifact/include/nested/file"), "Some /local")
    }

    func testProcessingRawArtifactDoesntReplacesInNonIncludeDir() throws {
        try fileAccessor.write(toPath: "/artifact/some/file", contents: "Some $(SRCROOT)")

        try processor.process(rawArtifact: "/artifact")

        XCTAssertEqual(try fileAccessor.contents(atPath: "/artifact/some/file"), "Some $(SRCROOT)")
    }

    func testDoesntProcessEmptyFiles() throws {
        try fileAccessor.write(toPath: "/artifact/include/.hidden", contents: "Some $(SRCROOT)")

        try processor.process(rawArtifact: "/artifact")

        XCTAssertEqual(try fileAccessor.contents(atPath: "/artifact/include/.hidden"), "Some $(SRCROOT)")
    }

    func testGeneratesOverrideFileBeforeRemappingToLocalPaths() throws {
        try fileAccessor.write(toPath: "/artifact/include/Module-Swift.h", contents: "Some $(SRCROOT)")

        try processor.process(rawArtifact: "/artifact")

        XCTAssertEqual(try fileAccessor.contents(atPath: "/artifact/include/Module-Swift.h.md5"), someSrcRootMd5Data)
    }

    func testGeneratesOverrideFileFromRemappedLocalFile() throws {
        try fileAccessor.write(toPath: "/artifact/include/Module-Swift.h", contents: "Some /local")

        try processor.process(localArtifact: "/artifact")

        XCTAssertEqual(try fileAccessor.contents(atPath: "/artifact/include/Module-Swift.h.md5"), someSrcRootMd5Data)
    }
}
