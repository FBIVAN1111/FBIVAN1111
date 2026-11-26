# Escape Reality MSIX packaging configuration.
# This is the ONLY file you normally need to edit. Both build scripts read it.
#
# IMPORTANT: Publisher must match the signing certificate's Subject exactly
# (including the "CN=" prefix), or Add-AppxPackage will reject the package.
# sign-and-install.ps1 creates a self-signed certificate with this Subject
# automatically, so the default below works out of the box for local sideloading.
@{
    IdentityName         = 'EscapeReality.App'
    Publisher            = 'CN=Escape Reality'
    PublisherDisplayName = 'Escape Reality'
    Version              = '1.0.1.0'
    ProcessorArchitecture = 'x64'
    AppExe               = 'EscapeReality.exe'
    # Local files that are NOT in the repo and NOT in the MSIX payload by
    # default: model weights, the model key, and the policy files. At build
    # time they are copied from here into the package under "data\".
    DataSource           = 'C:\ProgramData\EscapeReality'
}
