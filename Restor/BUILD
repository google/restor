load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("//:minimum_os.bzl", "MACOS_MINIMUM_OS")
load("//:signing_certificate.bzl", "expand_signing_certificate")

expand_signing_certificate(
    name = "SMPrivilegedExecutables",
    src = "SMPrivilegedExecutablesTemplate.plist",
)

objc_library(
    name = "restor_lib",
    srcs = [
        "Controllers/AppDelegate.h",
        "Controllers/AppDelegate.m",
        "Controllers/ViewControllers/AutoImageWarningViewController.h",
        "Controllers/ViewControllers/AutoImageWarningViewController.m",
        "Controllers/ViewControllers/CollectionViewItemAvailable.h",
        "Controllers/ViewControllers/CollectionViewItemAvailable.m",
        "Controllers/ViewControllers/CollectionViewItemImaging.h",
        "Controllers/ViewControllers/CollectionViewItemImaging.m",
        "Controllers/ViewControllers/ConfigViewController.h",
        "Controllers/ViewControllers/ConfigViewController.m",
        "Controllers/ViewControllers/CustomImageViewController.h",
        "Controllers/ViewControllers/CustomImageViewController.m",
        "Controllers/ViewControllers/DownloadImageViewController.h",
        "Controllers/ViewControllers/DownloadImageViewController.m",
        "Controllers/ViewControllers/MainViewController.h",
        "Controllers/ViewControllers/MainViewController.m",
        "Model/ConfigController.h",
        "Model/ConfigController.m",
        "Model/ImagingSession.h",
        "Model/ImagingSession.m",
        "Utilities/DiskWatcher.h",
        "Utilities/DiskWatcher.m",
        "Utilities/ErrorMaker.h",
        "Utilities/ErrorMaker.m",
        "Utilities/HashUtils.h",
        "Utilities/HashUtils.m",
        "Utilities/HelperToolUtils.h",
        "Utilities/HelperToolUtils.m",
        "Views/ImageNamedValueTransformer.h",
        "Views/ImageNamedValueTransformer.m",
        "main.m",
    ],
    asset_catalogs = glob(["Assets.xcassets/**"]),
    sdk_frameworks = [
        "DiskArbitration",
        "ServiceManagement",
    ],
    storyboards = glob(["**/*.storyboard"]),
    xibs = glob(["**/*.xib"]),
    deps = [
        "//Common:RestorProtocol",
        "@MOLAuthenticatingURLSession",
        "@MOLXPCConnection",
    ],
)

macos_application(
    name = "Restor",
    additional_contents = {
        "//restord:com.google.corp.restord": "Library/LaunchServices",
    },
    app_icons = glob(["Assets.xcassets/AppIcon.appiconset/*"]),
    bundle_id = "com.google.corp.Restor",
    infoplists = [
        "Info.plist",
        ":SMPrivilegedExecutables.plist",
    ],
    minimum_os_version = MACOS_MINIMUM_OS,
    visibility = ["//visibility:public"],
    deps = [":restor_lib"],
)
