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

// Reader of target dependencies that replaces raw dependencies
// according the virtual file system mappings
class OverlayDependenciesReader: DependenciesReader {

    enum MappingOrder {
        case localToVirtual
        case virtualToLocal
    }

    private let replacingKeys: (source: KeyPath<OverlayMapping, URL>, destination: KeyPath<OverlayMapping, URL>)
    // Underlying raw dependencies reader
    private let reader: DependenciesReader
    private let overlayReader: OverlayReader
    private var mappings: [OverlayMapping]?


    init(
        mode: MappingOrder,
        rawReader: DependenciesReader,
        overlayReader: OverlayReader
    ) {
        reader = rawReader
        self.overlayReader = overlayReader
        switch mode {
        case .localToVirtual:
            replacingKeys = (source: \.local, destination: \.virtual)
        case .virtualToLocal:
            replacingKeys = (source: \.virtual, destination: \.local)
        }
    }

    // Warning: this function is not thread safe
    private func getMappings() throws -> [OverlayMapping] {
        guard let readMappings = self.mappings else {
            let mappings = try overlayReader.provideMappings()
            self.mappings = mappings
            return mappings
        }
        return readMappings
    }

    // Warning: this function is not thread safe
    private func mapPath(_ path: String) throws -> String {
        guard let mapping = try getMappings().first(where: { $0[keyPath: replacingKeys.source].path == path }) else {
            // TODO: support partial mappings, where a directory path can be replaced with some other directory
            // no direct mapping found
            return path
        }
        return mapping[keyPath: replacingKeys.destination].path
    }

    private func mapPaths(_ paths: [String]) throws -> [String] {
        return try paths.map(mapPath)
    }

    func findDependencies() throws -> [String] {
        let rawDeps = try reader.findDependencies()
        return try mapPaths(rawDeps)
    }

    func findInputs() throws -> [String] {
        let rawInputs = try reader.findInputs()
        return try mapPaths(rawInputs)
    }

    func readFilesAndDependencies() throws -> [String: [String]] {
        let readFilesAndDependencies = try reader.readFilesAndDependencies()
        return try readFilesAndDependencies.reduce([:]) { (partialResult, arg1) in
            let (file, dependencies) = arg1
            var result = partialResult
            let newKey = try mapPath(file)
            let previousDeps = result[newKey] ?? []
            result[newKey] = try Set(mapPaths(dependencies) + previousDeps).sorted()
            return result
        }
    }
}
