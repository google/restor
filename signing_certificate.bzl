"""Fill in the CN for a plist from objc.signing_certificate_name"""

def _expand_signing_certificate(ctx): 
    ctx.actions.expand_template(
        template = ctx.file.src,
        output=ctx.outputs.out,
        substitutions = {
            "{SIGNING_CERTIFICATE}": ctx.fragments.objc.signing_certificate_name,
         },
    )

expand_signing_certificate = rule(
    attrs = {
        "src": attr.label(allow_single_file = True),
    },
    fragments = ["objc"],
    outputs = {"out": "%{name}.plist"},
    implementation = _expand_signing_certificate,
)
