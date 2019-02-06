load("@build_bazel_rules_apple//apple:macos.bzl", "macos_command_line_application")
load("//:minimum_os.bzl", "MACOS_MINIMUM_OS")
load("//:signing_certificate.bzl", "expand_signing_certificate")

expand_signing_certificate(
    name = "SMAuthorizedClients",
    src = "SMAuthorizedClientsTemplate.plist",
)

objc_library(
    name = "restord_lib",
    srcs = [
        "Daemon.h",
        "Daemon.m",
        "ImageSessionServer.h",
        "ImageSessionServer.m",
        "main.m",
    ],
    deps = [
        "//Common:RestorProtocol",
        "@MOLXPCConnection",
    ],
)

macos_command_line_application(
    name = "com.google.corp.restord",
    bundle_id = "com.google.corp.restord",
    infoplists = [
        "Info.plist",
        ":SMAuthorizedClients.plist",
    ],
    launchdplists = ["launchd.plist"],
    minimum_os_version = MACOS_MINIMUM_OS,
    visibility = ["//visibility:public"],
    deps = [":restord_lib"],
)
