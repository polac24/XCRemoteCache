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

import Foundation

public class XCACTool {
    private let args: [String]
    private let objcOutput: String?
    private let swiftOutput: String?
    private let shellOut: ShellOut

    public init(
        args: [String],
        objcOutput: String?,
        swiftOutput: String?
    ) {
        self.args = args
        self.objcOutput = objcOutput
        self.swiftOutput = swiftOutput
        self.shellOut = ProcessShellOut()
    }

    public func run() throws {
        let fileManager = FileManager.default
        let fileAccessor: FileAccessor = fileManager
        let config: XCRemoteCacheConfig
        let context: ACToolContext
        let srcRoot: URL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        config = try XCRemoteCacheConfigReader(srcRootPath: srcRoot.path, fileReader: fileAccessor)
            .readConfiguration()
        context = try ACToolContext(
            config: config,
            objcOutput: objcOutput,
            swiftOutput: swiftOutput
        )

        let markerReader = FileMarkerReader(context.markerURL, fileManager: fileAccessor)
        let markerWriter = FileMarkerWriter(context.markerURL, fileAccessor: fileAccessor)
        let fingerprintAccumulator = FingerprintAccumulatorImpl(algorithm: MD5Algorithm(), fileManager: fileManager)
        let metaPathProvider = ArtifactMetaPathProvider(
            artifactLocation: context.activeArtifactLocation,
            dirScanner: fileManager
        )
        let metaReader = JsonMetaReader(fileAccessor: fileManager)

        // Let the command run first. The actool should be really quick as it only transforms .xcassets' json(s)
        // to .h and .swift files
        try fallbackToDefaultAndWait(command: config.actoolCommand, args: args)

        let acTool = ACTool(
            markerReader: markerReader,
            metaReader: metaReader,
            fingerprintAccumulator: fingerprintAccumulator,
            metaPathProvider: metaPathProvider
        )

        let acResult: ACToolResult
        do {
            acResult = try acTool.run()
        } catch {
            infoLog("\(config.actoolCommand) wrapper failed with an error \(error)")
            acResult = .cacheMiss
        }

        do {
            switch acResult {
            case .cacheHit(let dependencies):
                try markerWriter.enable(dependencies: dependencies)
            default:
                try markerWriter.disable()
            }
        } catch {
            // separate invocations as os_log truncates long messages
            errorLog("Failure in \(config.actoolCommand) marker setup with cache \(acResult)")
            errorLog("\(error)")
            // to not risk over-cashing when disabling XCRC failed, we have force-stop the build
            exit(1)
        }
    }

    private func fallbackToDefaultAndWait(command: String = "actool", args: [String]) throws {
        debugLog("Fallbacking with \(command) \(args.dropFirst())")
        do {
            try shellOut.callExternalProcessAndWait(
                command: command,
                invocationArgs: Array(args.dropFirst()),
                envs: ProcessInfo.processInfo.environment
            )
        } catch ShellError.statusError(_, let exitCode) {
            exit(exitCode)
        }
    }
}

