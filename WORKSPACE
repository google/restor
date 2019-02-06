workspace(name = "restor")

load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

git_repository(
    name = "build_bazel_rules_apple",
    remote = "https://github.com/bazelbuild/rules_apple.git",
    tag = "0.13.0",
)

load(
    "@build_bazel_rules_apple//apple:repositories.bzl",
    "apple_rules_dependencies",
)

apple_rules_dependencies()

#Macops MOL* dependencies
git_repository(
    name = "MOLAuthenticatingURLSession",
    remote = "https://github.com/google/macops-molauthenticatingurlsession.git",
    tag = "v2.5",
)

git_repository(
    name = "MOLCertificate",
    remote = "https://github.com/google/macops-molcertificate.git",
    tag = "v2.0",
)

git_repository(
    name = "MOLCodesignChecker",
    remote = "https://github.com/google/macops-molcodesignchecker.git",
    tag = "v2.0",
)

git_repository(
    name = "MOLXPCConnection",
    remote = "https://github.com/google/macops-molxpcconnection.git",
    tag = "v2.0",
)
