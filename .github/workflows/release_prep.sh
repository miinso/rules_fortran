#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

TAG=${1:-${GITHUB_REF_NAME}}
PREFIX="rules_fortran-${TAG:1}"
ARCHIVE="rules_fortran-$TAG.tar.gz"

git archive --format=tar --prefix=${PREFIX}/ ${TAG} | gzip > $ARCHIVE
SHA=$(shasum -a 256 $ARCHIVE | awk '{print $1}')

cat << EOF
## Using bzlmod:

Add to your \`MODULE.bazel\` file:

\`\`\`starlark
bazel_dep(name = "rules_fortran", version = "${TAG:1}")
\`\`\`

## Using WORKSPACE:

\`\`\`starlark
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "rules_fortran",
    sha256 = "${SHA}",
    strip_prefix = "${PREFIX}",
    url = "https://github.com/miinso/rules_fortran/releases/download/${TAG}/${ARCHIVE}",
)
\`\`\`
EOF
