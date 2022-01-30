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
typealias OverlayMapping = (virtual: URL, local :URL)

enum YamlOverlayReaderError: Error {
    /// The source file is missing
    case missingSourceFile(URL)
    /// The file exists but its content is invalid
    case invalidSourceContent(URL)
}
/// Provides virtual file system overlay mappings
protocol OverlayReader {
    func provideMappings() throws -> [OverlayMapping]
}

class YamlOverlayReader: OverlayReader {

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
    private let yaml: URL
    private let fileReader: FileReader


    init(_ yaml: URL, fileReader: FileReader) {
        self.yaml = yaml
        self.fileReader = fileReader
    }

    func provideMappings() throws -> [OverlayMapping] {
        guard let yamlContent = try fileReader.contents(atPath: yaml.path) else {
            throw YamlOverlayReaderError.missingSourceFile(yaml)
        }

        let overlay: Overlay = try jsonDecoder.decode(Overlay.self, from: yamlContent)

        
        return []
    }

}
