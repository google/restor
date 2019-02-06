package(default_visibility = ["//visibility:public"])

objc_library(
    name = "Disk",
    srcs = ["Disk.m"],
    hdrs = ["Disk.h"],
    sdk_frameworks = ["DiskArbitration"],
)

objc_library(
    name = "Image",
    srcs = ["Image.m"],
    hdrs = ["Image.h"],
)

objc_library(
    name = "RestorProtocol",
    hdrs = ["RestorProtocol.h"],
    deps = [
        ":Disk",
        ":Image",
    ],
)
