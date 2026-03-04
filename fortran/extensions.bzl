"""Bzlmod extensions for rules_fortran."""

load("//fortran:repositories.bzl", "flang_register_toolchains")

# Default configuration
_DEFAULT_VERSION = "v21.1.8"
_DEFAULT_REPO_OWNER = "miinso"
_DEFAULT_REPO_NAME = "flang-releases"

# script-generated from each release's SHA256SUMS.txt
_CHECKSUMS = {
    "v20.1.0": {
        "aarch64-unknown-linux-gnu": "a1a500cf61fc8dcebfa77ea74eed129d10025b76fe99199c4e8340de0a10393b",
        "arm64-apple-darwin": "f045c7e1ee0320ea0c4d1b1d824649d16f8ac0a7cfcbfd232c6df3367864b3f3",
        "x86_64-apple-darwin": "5d50c1f5b911086c3b6dfd6fb4fc587a9e68ac2d8ac3187cc2fb64d348c67462",
        "x86_64-pc-windows-msvc": "7fac672ea25307ec891456dcdd0a3533dded703a09f56f0800d8d616b814a000",
        "x86_64-unknown-linux-gnu": "bea0d00e5ab1fce1812b68fe3070c3f4bcb39c51c91c2bdffcd7b40b19475b95",
    },
    "v20.1.2": {
        "aarch64-unknown-linux-gnu": "07b3ebde2f895b3132e83db5f59445d51ad160850ca4df1f4354227c8eb236e6",
        "arm64-apple-darwin": "721abd335a1ab5180e6a0b1b8ef4acdf97aafbed19e42d7f47dbfc49a3817504",
        "x86_64-apple-darwin": "33acfa2df86c3b5d503e1f7dde27b01c07df94a93ddd01d219c314bccec6d257",
        "x86_64-pc-windows-msvc": "e4f93372fb159b0135fbaca44641ee09d8f8f3f8c8d1a20fd4cd73330498eb47",
        "x86_64-unknown-linux-gnu": "5a32b604a7ea7bade6cbc7a23caff36b54f9bd3901edf74b03383c08d4458862",
    },
    "v20.1.3": {
        "aarch64-unknown-linux-gnu": "e6112db5da7f59ca8870f3280f095601e9f183e326db7b718bec10671239a49e",
        "arm64-apple-darwin": "58d05473c2317b4763b7d91d3b6beafc300c0c6aca57f54a7b97ecfd8b319465",
        "x86_64-apple-darwin": "41f02294da8cd439d4261aff5c5685bb7cb90cff42b74020edfeb7dad03d4b8b",
        "x86_64-pc-windows-msvc": "9464c52c9d87f442db1898e28360040e65333fcc0265468ef1969800f0bfb1e4",
        "x86_64-unknown-linux-gnu": "9528c880ef2a09a139dc47d6192312038d76320219db2bb40fa7e30ae23bdeab",
    },
    "v20.1.4": {
        "aarch64-unknown-linux-gnu": "20d9fe4edd07b218e42cec65f37f7a2fd0c2117be93a1b817fc8c3a854ebc402",
        "arm64-apple-darwin": "458d5b048ade364dad78e17c59c6cced30d578e35ee12983d5baae2fa0e230bc",
        "x86_64-apple-darwin": "a0a99baa00662a3df144326d6ee9d20b8867b01e9bcf93a62567b43269bfadec",
        "x86_64-pc-windows-msvc": "b36e2284a7b55d75a4f2d7138d64a94a9a353304f5fdb0c2a6fe9acc6792190d",
        "x86_64-unknown-linux-gnu": "4f5140e3bd9bdfd00f440086c5e2279865ca209423619250848cc3ee6eccbde6",
    },
    "v20.1.5": {
        "aarch64-unknown-linux-gnu": "487ffa4aa21fbed877310cc40b7b7d6430b73af0f5f03b21d84e9da25aed2461",
        "arm64-apple-darwin": "f78e444b71ed955ed29cc6cae84eb3df3984173ddc53fe8a72472a880af3e3d5",
        "x86_64-apple-darwin": "93a53020ecd253de2c105bd2f54b0f662ab4ec0af4274f36fa5943e7c5e98582",
        "x86_64-pc-windows-msvc": "a61915941b680c95b66837cb99123923207edd002115e82156c3b8b029684709",
        "x86_64-unknown-linux-gnu": "cdf18fe23d6d5f29ea211ddd0e85ff0ddb25353893f915418b6304335d589a70",
    },
    "v20.1.7": {
        "aarch64-unknown-linux-gnu": "7705398a888ff6644d707c4e4d4e99892795c53dbfd399eb4cb42dbab17f0c7a",
        "arm64-apple-darwin": "e50c23cfc5e2d170e8e6bb27f7694dee2f90548a6f97546bb22d72051181e6da",
        "x86_64-apple-darwin": "bb81debd3e4d25bbffd276bc0ebf5e9bfc9f1b5528bfb319bcc4c00ea40e8aa0",
        "x86_64-pc-windows-msvc": "5aea1249a59d1ab4d73056083a65d8afdc7af7441abb1a467b8cdd98a9e55d3d",
        "x86_64-unknown-linux-gnu": "4e8184a751d753e1c922cb0d060fcd138654a0b30f07faf447490d3a99b7d562",
    },
    "v20.1.8": {
        "aarch64-unknown-linux-gnu": "43178c1d9409677a4896ec567ce72f9e80460b43f7d1afa7e4b16ec8695b625d",
        "arm64-apple-darwin": "cb93b5a2bde91662dbcef3c3e3796535f434b0d1e9ea99b5360ec6d491a688aa",
        "x86_64-apple-darwin": "19b5b80b8ddbc6f67e374ce73d8b1f70a4f4bfa49c6b7c683ff6b1c5adbc0873",
        "x86_64-pc-windows-msvc": "c1ad08683754beb2dea7702230346d526adb0fa3c8b7ab9d967d3b526b25cedb",
        "x86_64-unknown-linux-gnu": "7acd5ca9d0b282130126964acf61ef9cc85e86f818ed659edc2db4523ee3346f",
    },
    "v21.1.0": {
        "aarch64-unknown-linux-gnu": "b71577ec10c7fa66b73fbe844505e586b3649d8a971cb8f6fa2028391f0571a4",
        "arm64-apple-darwin": "5f10ee71c7d6b58ecf82e305ecda26794245425d1484fea8f788658bf76b7192",
        "x86_64-apple-darwin": "1fa30aa31119fcbdbcf50cdd94835c3498eef6494de0b746312bdd7cbc62dd4d",
        "x86_64-pc-windows-msvc": "06d9c09a86757e17d31b7c36fe45ce31b9b03fc1b72932338a009c88b9a228bb",
        "x86_64-unknown-linux-gnu": "5d835c5e8cf4f148c080f848fc81a78aafd1e23921ab82fa848e82cc4ceb7a84",
    },
    "v21.1.1": {
        "aarch64-unknown-linux-gnu": "a4415ba81221349a5cc98c83a3fc1b6784e7ae676e5832850ca7ec73d7958d23",
        "arm64-apple-darwin": "2c0a3c055c16fcf6dabc1a8991afdc2fbc7519b8cd46cc5359ba0a3b9e839f63",
        "x86_64-apple-darwin": "845b106001e475a333c714e1125f24cd72c257fe0bb72f61e6aec1cdb3cb3a1f",
        "x86_64-pc-windows-msvc": "bb2b93b6c9d2b259dba60c3c91f66480d3f8d37843feb1fcded005c7a1cca836",
        "x86_64-unknown-linux-gnu": "220f6355aaff84fe3d11afd434c90279e201fc6581815a6c802d543afc2a484a",
    },
    "v21.1.2": {
        "aarch64-unknown-linux-gnu": "63298044736475ec402c61926c1e95c73b47804c07ac5c3483d3723f02d18ff6",
        "arm64-apple-darwin": "96057aaaaf6df0f1595e587d6a128260469f237b7c9fa153a7d76295c56e8b45",
        "x86_64-apple-darwin": "970d0fd57593218adb914c05c0db457f3cb6c2cb6462f90d491b11d4dfab04c7",
        "x86_64-pc-windows-msvc": "3d74498d02daee32b5e8abf4f7a18fe6b2f1fad8a33f14edc4b7d92f21f8f99a",
        "x86_64-unknown-linux-gnu": "5d6bba5c6f62430bb157f840c5a10a2d875923ef0d5deb2728023f679fbcee22",
    },
    "v21.1.3": {
        "aarch64-unknown-linux-gnu": "87081212ab0592e0a7781620305685544a19a11d4d4890d32ac43bcca10bf36b",
        "arm64-apple-darwin": "5b4a3dac0119529b87cbaf7c7c228f9745c3ebae8eebef42573f2c100f3e76a1",
        "x86_64-apple-darwin": "ba53c1ba6906c1af0e2090353fc15b112ea84904bf2f77d760ea7202dc8c9a38",
        "x86_64-pc-windows-msvc": "28f05c93eb056e5a82c8aa47c2829c913a76511396d5ef89bd52b2e32271e8ea",
        "x86_64-unknown-linux-gnu": "f781528ddd3ead5d18ccd88962e3e01d20f2db4569b24d4cf4daa37c3b35419f",
    },
    "v21.1.4": {
        "aarch64-unknown-linux-gnu": "e61b9acbe7f6b1fbdcf47be0c890e69216037c4daf9f1413abdd4981a387cf2b",
        "arm64-apple-darwin": "24e32ac068636c993e5f4a6a1826fcd7ea66594a3444214053330e649cdfbfdf",
        "x86_64-apple-darwin": "9e18f93a577520b7f34e72ff9adefd07970b67a96db8098548f94cf2242c8383",
        "x86_64-pc-windows-msvc": "31381ce36e5b21eb1bae90c3b84a53ac1d7532e036eed938e7ba6322026bc256",
        "x86_64-unknown-linux-gnu": "34e35a178c1f0c79233df4b2d21f96d5f175f8a5b9bca4e04fd4934d9be4e18b",
    },
    "v21.1.5": {
        "aarch64-unknown-linux-gnu": "ea72c490777c48b07fd06bf7cb82d114215c058cfaaeda3fdb441a02cee405ab",
        "arm64-apple-darwin": "8a64823f41c776e949e61a59bf3e59c237fe7ce8833126193f7bc80fe81291ed",
        "x86_64-apple-darwin": "3c4fc8abf528cb22019c3c76be61ba1f8ffe26fc151129af1c79684844771900",
        "x86_64-pc-windows-msvc": "28f6cc4c8d88ab521612f1e03910eef82b12c57899297479c0e406af5b15369c",
        "x86_64-unknown-linux-gnu": "0d72c8440db7bf310a58e63fb59006fb87452044bbb9afb58382c9d71dbc6d08",
    },
    "v21.1.6": {
        "aarch64-unknown-linux-gnu": "6a96c273461684cf35ac7d43f826f62b7baace9b28f5a0a6305228522c269ccf",
        "arm64-apple-darwin": "a8bfd5e04282aff73a3f775c457a0cfbacc68476a9fd4213205019c110e326e7",
        "x86_64-apple-darwin": "478bd5231009cb66999a5f5179ae1c77ed16163a61d5304ada202bb5114b93dc",
        "x86_64-pc-windows-msvc": "040206234f03d96eb13e9ffb8052fd62d2c64d5ab11e95ab9b1f5b86971d3587",
        "x86_64-unknown-linux-gnu": "b39d3944bbc0392e706d2ae9ad80e8091ad6354274e489376e641a5ccc76df1f",
    },
    "v21.1.7": {
        "aarch64-unknown-linux-gnu": "850064475bd761f25a9b76229532d5c9f8dc7251465c206be506189de8eef72f",
        "arm64-apple-darwin": "3f1736d5e27c50185e2fb88ea2aab3ba7ac9824c0c76eca597519c1563fb282d",
        "x86_64-apple-darwin": "71e628ce6af2fcecb6d475288ac955e19c32e857a21aa0957503bc3d71abaa10",
        "x86_64-pc-windows-msvc": "99b8c0c3022da47944dc49f2b85093ddf988297d8ac3393a3c75a314400a945f",
        "x86_64-unknown-linux-gnu": "d32c448a0a0ca12f31f7479b774dd322af9e0470b9dc8962c9fdba7bf3f1cb0d",
    },
    "v21.1.8": {
        "aarch64-unknown-linux-gnu": "0b2f6a9e4192c04644f51c067b449405e00b1e4e8d8ee9bd510657130fdb7290",
        "arm64-apple-darwin": "89cbbe09bb35fac6ec1781b74637e40a58eddc89475d6a6a1e49c0b15a6c5eb5",
        "x86_64-apple-darwin": "646569273468ead05343c8497f21dd9a2dcf75bff6e40ff6b71090e27ba6f866",
        "x86_64-pc-windows-msvc": "b25e8c506e1b1851d2b80518205a7a750e0363408919566e90b4ff7b8b367e6c",
        "x86_64-unknown-linux-gnu": "673f4dc1e95d09b1253ca32078ae058540d68b533bdcbcbf72b7242fbed82dc6",
    },
    "v22.1.0": {
        "aarch64-unknown-linux-gnu": "8a473cd6bf083457dc1fd07c7060c11cbde882b87ec836a80d7e76eee4d9d675",
        "arm64-apple-darwin": "33b153ced65e8443115b5497849610dad941ce50b2b5aba9fb8ba2ff2150ca6f",
        "x86_64-apple-darwin": "d43f4162c7817e304cbc8155bd7c24f0b8acecde5b1d7fa097259d7a1fa75158",
        "x86_64-pc-windows-msvc": "9693475278561c5d54a9bbb4dade80ad1f88c0efeb2a08503a64f63b8d847dba",
        "x86_64-unknown-linux-gnu": "577091102d2720bed921d467d3b680ccd515eec59fedf10281242674bfd10a93",
    },
}

_version_tag = tag_class(attrs = {
    "version": attr.string(default = _DEFAULT_VERSION),
    "sha256": attr.string_dict(default = {}),
})

def _flang_impl(module_ctx):
    """Implementation of flang extension."""
    version = _DEFAULT_VERSION
    sha256 = {}
    for mod in module_ctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            if tag.version:
                version = tag.version
            if tag.sha256:
                sha256 = dict(tag.sha256)

    # fall back to built-in checksums if no explicit sha256 provided
    if not sha256 and version in _CHECKSUMS:
        sha256 = dict(_CHECKSUMS[version])

    flang_register_toolchains(
        name = "flang",
        version = version,
        repo_owner = _DEFAULT_REPO_OWNER,
        repo_name = _DEFAULT_REPO_NAME,
        sha256 = sha256,
    )

flang = module_extension(
    implementation = _flang_impl,
    tag_classes = {"version": _version_tag},
    doc = """Module extension for Flang toolchains.

    Invoked by rules_fortran. You just need:

        bazel_dep(name = "rules_fortran")

    To override the version:

        flang = use_extension("@rules_fortran//fortran:extensions.bzl", "flang")
        flang.version(version = "v21.1.8")
    """,
)
