// The Swift package is a source-only Mac executable, not an iPhone app project.
#if SWIFT_PACKAGE && !os(macOS)
#error("AsunaTracksMac is a Mac-only Swift package. Open AsunaTracks.xcodeproj and select the AsunaTracks scheme for iPhone/iPad, or AsunaTracksWatch for Apple Watch.")
#endif
