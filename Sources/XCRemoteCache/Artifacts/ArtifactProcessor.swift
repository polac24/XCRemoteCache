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

import Foundation


/// Performs a pre/postprocessing on an artifact package
/// Coule be a place for file reorganization (to support legacy package formats) and/or
/// remapp absolute paths in some package files
protocol ArtifactProcessor {
    /// Processes a raw artifact in a directory. Raw artifact is a format of an artifact
    /// that is stored in a remote cache server (generic)
    /// - Parameter rawArtifact: directory that contains raw artifact content
    func process(rawArtifact: URL) throws

    /// Processes a local artifact in a directory
    /// - Parameter localArtifact: directory that contains local (machine-specific) artifact content
    func process(localArtifact: URL) throws
}
