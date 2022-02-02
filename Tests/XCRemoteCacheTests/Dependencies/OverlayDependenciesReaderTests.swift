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

class OverlayDependenciesReaderTests: XCTestCase {
    private let dependenciesReader = DependenciesReaderFake(
        dependencies: ["/source.swift": ["/Intermediate/Some/file.h"]]
    )
    private let overlayReader = OverlayReaderFake(
        mappings: [.init(virtual: "/file.h", local: "/Intermediate/Some/file.h")]
    )

    func testMappingFromLocalToVirtual() throws {
        let reader = OverlayDependenciesReader(
            mode: .localToVirtual,
            rawReader: dependenciesReader,
            overlayReader: overlayReader
        )

        let dependencies = try reader.findDependencies()
        XCTAssertEqual(dependencies, ["/file.h"])
    }

    func testMappingFromVirtualToLocal() throws {
        let dependenciesReader = DependenciesReaderFake(
            dependencies: ["/source.swift": ["/file.h"]]
        )
        let reader = OverlayDependenciesReader(
            mode: .virtualToLocal,
            rawReader: dependenciesReader,
            overlayReader: overlayReader
        )

        let dependencies = try reader.findDependencies()
        XCTAssertEqual(dependencies, ["/Intermediate/Some/file.h"])
    }

    func testFilesAndDependenciesFromLocalToVirtualKeys() throws {
        let dependenciesReader = DependenciesReaderFake(
            dependencies: [
                "/Intermediate/Some/file.h": ["/file+Extra.h"],
            ]
        )
        let reader = OverlayDependenciesReader(
            mode: .localToVirtual,
            rawReader: dependenciesReader,
            overlayReader: overlayReader
        )

        let dependencies = try reader.readFilesAndDependencies()
        XCTAssertEqual(dependencies, ["/file.h": ["/file+Extra.h"]])
    }

    func testFilesAndDependenciesFromLocalToVirtualValues() throws {
        let dependenciesReader = DependenciesReaderFake(
            dependencies: [
                "/file2.h": ["/Intermediate/Some/file.h"],
            ]
        )
        let reader = OverlayDependenciesReader(
            mode: .localToVirtual,
            rawReader: dependenciesReader,
            overlayReader: overlayReader
        )

        let dependencies = try reader.readFilesAndDependencies()
        XCTAssertEqual(dependencies, ["/file2.h": ["/file.h"]])
    }

    func testFilesAndDependenciesFromVirtualToLocalKeys() throws {
        let dependenciesReader = DependenciesReaderFake(
            dependencies: [
                "/file.h": ["/file+Extra.h"],
            ]
        )
        let reader = OverlayDependenciesReader(
            mode: .virtualToLocal,
            rawReader: dependenciesReader,
            overlayReader: overlayReader
        )

        let dependencies = try reader.readFilesAndDependencies()
        XCTAssertEqual(dependencies, ["/Intermediate/Some/file.h": ["/file+Extra.h"]])
    }

    func testFilesAndDependenciesFromVirtualToLocalValues() throws {
        let dependenciesReader = DependenciesReaderFake(
            dependencies: [
                "/file2.h": ["/file.h"],
            ]
        )
        let reader = OverlayDependenciesReader(
            mode: .virtualToLocal,
            rawReader: dependenciesReader,
            overlayReader: overlayReader
        )

        let dependencies = try reader.readFilesAndDependencies()
        XCTAssertEqual(dependencies, ["/file2.h": ["/Intermediate/Some/file.h"]])
    }

    func testVirtualDependencyLocationsAreMerged() throws {
        let dependenciesReader = DependenciesReaderFake(
            dependencies: [
                "/Intermediate/Some/file.h": ["/file.h"],
                "/file.h": ["/file+Extra.h"]
            ]
        )
        let reader = OverlayDependenciesReader(
            mode: .localToVirtual,
            rawReader: dependenciesReader,
            overlayReader: overlayReader
        )

        let dependencies = try reader.readFilesAndDependencies()
        XCTAssertEqual(Set(dependencies.keys), ["/file.h"])
        XCTAssertEqual(dependencies["/file.h"].map(Set.init), ["/file+Extra.h", "/file.h"])
    }

    func testVirtualDependenciesAreMerged() throws {
        let dependenciesReader = DependenciesReaderFake(
            dependencies: [
                "/Intermediate/Some/file.h": ["/Intermediate/Some/file.h"],
                "/file.h": ["/file.h"]
            ]
        )
        let reader = OverlayDependenciesReader(
            mode: .localToVirtual,
            rawReader: dependenciesReader,
            overlayReader: overlayReader
        )

        let dependencies = try reader.readFilesAndDependencies()
        XCTAssertEqual(dependencies, ["/file.h": ["/file.h"]])

    }
}

