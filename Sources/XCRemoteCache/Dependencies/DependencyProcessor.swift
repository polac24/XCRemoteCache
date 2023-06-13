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

/// Representation of a single compilation dependency
public struct Dependency: Equatable {
    public enum Kind {
        case xcode
        case product
        case source
        case fingerprint
        case intermediate
        case derivedFile
        // Product of the target itself
        case ownProduct
        // User-excluded path
        case userExcluded
        // the on-fly .swift/.h file that contains all assets references (colors&images)
        case generatedAssetSymbol
        case unknown
    }

    public let url: URL
    public let type: Kind

    public init(url: URL, type: Kind) {
        self.url = url
        self.type = type
    }
}

/// A pseudo-type that classifies all dependencies into two buckets:
/// fingerprintScoped: all these files have to be included in the fingerprint
/// extra: all other deps
typealias DependencyProcessorResult = (
    fingerprintScoped: [Dependency],
    assetsSource: [Dependency],
    extra: [Dependency]
)

/// Processes raw compilation URL dependencies from .d files
protocol DependencyProcessor {
    /// Processes a list of dependencies and provides a list of project-specific dependencies
    /// - Parameter files: raw dependency locations
    /// - Returns: array of project-specific dependencies
    func process(_ files: [URL]) -> DependencyProcessorResult
}

/// Classifies raw dependencies and strips irrelevant dependencies
class DependencyProcessorImpl: DependencyProcessor {
    /// Name of a file that is auto-generated by Xcode with all assets references and placed in
    /// the DerivedSources/ dir
    static let GENERATED_ASSETS_FILENAME = "GeneratedAssetSymbols"

    private let xcodePath: String
    private let productPath: String
    private let sourcePath: String
    private let intermediatePath: String
    private let derivedFilesPath: String
    private let bundlePath: String?
    private let skippedRegexes: [String]

    init(xcode: URL, product: URL, source: URL, intermediate: URL, derivedFiles: URL, bundle: URL?, skippedRegexes: [String]) {
        xcodePath = xcode.path.dirPath()
        productPath = product.path.dirPath()
        sourcePath = source.path.dirPath()
        intermediatePath = intermediate.path.dirPath()
        derivedFilesPath = derivedFiles.path.dirPath()
        bundlePath = bundle?.path.dirPath()
        self.skippedRegexes = skippedRegexes
    }

    func process(_ files: [URL]) -> DependencyProcessorResult {
        let dependencies = classify(files)
        return split(allDependencies: dependencies)
    }

    private func split(allDependencies: [Dependency]) -> DependencyProcessorResult {
        var fingerprintScoped: [Dependency] = []
        var assetsSources: [Dependency] = []
        var extra: [Dependency] = []
        allDependencies.forEach { dep in
            if isFingerprintRelevantDependency(dep) {
                fingerprintScoped.append(dep)
            } else if isAssetsSourcesDependency(dep) {
                assetsSources.append(dep)
            } else {
                extra.append(dep)
            }
        }
        return (fingerprintScoped, assetsSources, extra)
    }

    private func classify(_ files: [URL]) -> [Dependency] {
        return files.map { file -> Dependency in
            let filePath = file.resolvingSymlinksInPath().path
            if skippedRegexes.contains(where: { filePath.range(of: $0, options: .regularExpression) != nil }) {
                return Dependency(url: file, type: .userExcluded)
            } else if filePath.hasPrefix(xcodePath) {
                return Dependency(url: file, type: .xcode)
            } else if filePath.hasPrefix(derivedFilesPath) &&
                        filePath.hasSuffix("/\(Self.self.GENERATED_ASSETS_FILENAME).swift") ||
                        filePath.hasSuffix("/\(Self.self.GENERATED_ASSETS_FILENAME).h"
                ) {
                    // Starting Xcode 15.0, the filename of that file is static
                    // and placed in DerivedSources, e.g.
                    // /DerivedData/Build/Intermediates.noindex/xxx.build/Debug-iphonesimulator/xxx.build/DerivedSources/GeneratedAssetSymbols.swift

                    return Dependency(url: file, type: .generatedAssetSymbol)
                }
            else if filePath.hasPrefix(intermediatePath) {
                return Dependency(url: file, type: .intermediate)
            } else if filePath.hasPrefix(derivedFilesPath) {
                return Dependency(url: file, type: .derivedFile)
            } else if let bundle = bundlePath, filePath.hasPrefix(bundle) {
                // If a target produces a bundle, explicitly classify all
                // of products to distinguish from other targets products
                return Dependency(url: file, type: .ownProduct)
            } else if filePath.hasPrefix(productPath) {
                return Dependency(url: file, type: .product)
            } else if filePath.hasPrefix(sourcePath) {
                return Dependency(url: file, type: .source)
            } else {
                return Dependency(url: file, type: .unknown)
            }
        }
    }

    private func isFingerprintRelevantDependency(_ dependency: Dependency) -> Bool {
        // Generated modulemaps may not be an actual dependency. Swift selects them as a
        // dependency because these contribute to the final module context but doesn't mean that given module has
        // been imported and it should invalidate current target when modified

        // TODO: Recognize if the generated module was actually imported and only then it should be considered
        // as a valid Dependency
        if dependency.type == .product && dependency.url.pathExtension == "modulemap" {
            return false
        }

        // Skip:
        // - A fingerprint generated includes Xcode version build number so no need to analyze prepackaged Xcode files
        // - All files in `*/Interemediates/*` - this file are created on-fly for a given target (except of GeneratedAssetSymbols.swift)
        // - Some files may depend on its own product (e.g. .m may #include *-Swift.h) - we know products will match
        //   because in case of a hit, these will be taken from the artifact
        // - Customized DERIVED_FILE_DIR may change a directory of
        //   derived files, which by default is under `*/Interemediates`
        // - User-specified (in .rcinfo) files to exclude
        // - on-fly generated assets symbols, as these will not be available yet when a prebuild script is invoked
        let irrelevantDependenciesType: [Dependency.Kind] = [
            .xcode, .intermediate, .ownProduct, .derivedFile, .userExcluded, .generatedAssetSymbol,
        ]
        return !irrelevantDependenciesType.contains(dependency.type)
    }

    private func isAssetsSourcesDependency(_ dependency: Dependency) -> Bool {
        dependency.type == .generatedAssetSymbol
    }
}

fileprivate extension String {
    func dirPath() -> String {
        hasSuffix("/") ? self : appending("/")
    }
}
