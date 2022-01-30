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

/// Maps overlay's virtual URL with an actual (local) location
struct OverlayMapping: Hashable {
    let virtual: URL
    let local: URL
}

enum JsonOverlayReaderError: Error {
    /// The source file is missing
    case missingSourceFile(URL)
    /// The file exists but its content is invalid
    case invalidSourceContent(URL)
    /// the y
    case unsupportedFormat
}
/// Provides virtual file system overlay mappings
protocol OverlayReader {
    func provideMappings() throws -> [OverlayMapping]
}

class JsonOverlayReader: OverlayReader {

    private struct Overlay: Decodable {
        enum OverlayType: String, Decodable {
            case file
            case directory
        }

        struct Content: Decodable {
            let externalContents: String
            let name: String
            let type: OverlayType

            enum CodingKeys: String, CodingKey {
                case externalContents = "external-contents"
                case name
                case type
            }
        }

        struct RootContent: Decodable {
            let contents: [Content]
            let name: String
            let type: OverlayType
        }
        let roots: [RootContent]
    }

    private lazy var jsonDecoder = JSONDecoder()
    private let json: URL
    private let fileReader: FileReader


    init(_ json: URL, fileReader: FileReader) {
        self.json = json
        self.fileReader = fileReader
    }

    func provideMappings() throws -> [OverlayMapping] {
        guard let jsonContent = try fileReader.contents(atPath: json.path) else {
            throw JsonOverlayReaderError.missingSourceFile(json)
        }

        let overlay: Overlay = try jsonDecoder.decode(Overlay.self, from: jsonContent)
        let mappings: [OverlayMapping] = try overlay.roots.reduce([]) { prev, root in
            switch root.type {
            case .directory:
                //iterate all contents
                let dir = URL(fileURLWithPath: root.name)
                let mappings: [OverlayMapping] = try root.contents.map { content in
                    switch content.type {
                    case .file:
                        let virtual = dir.appendingPathComponent(content.name)
                        let local = URL(fileURLWithPath: content.externalContents)
                        return .init(virtual: virtual, local: local)
                    case .directory:
                        throw JsonOverlayReaderError.unsupportedFormat
                    }

                }
                return prev + mappings
            case .file:
                throw JsonOverlayReaderError.unsupportedFormat
            }
        }

        return mappings
    }

}