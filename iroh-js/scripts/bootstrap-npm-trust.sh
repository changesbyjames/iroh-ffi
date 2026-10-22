#!/usr/bin/env bash
# Make every package the release workflow publishes trust it, so releases publish over OIDC with no stored token.
#
# npm can only trust a workflow for a package that already exists. So each package that is not on npm yet is first
# reserved with a placeholder version (0.0.0-bootstrap.0, under the `bootstrap` dist-tag, deprecated), then trusts
# .github/workflows/release_node.yml in this repository, in the `npm` environment. Packages that already exist or
# already trust a publisher are left alone, so it is safe to run again, for example after adding a platform.
#
# Run it once, from a machine logged in to npm (`npm login`) as an owner of the scope, with two-factor authentication
# on the account: npm asks for it on the first write. Set DRY_RUN=1 to print what it would do.
#
#   iroh-js/scripts/bootstrap-npm-trust.sh

set -euo pipefail

cd "$(dirname "$0")/.."

REGISTRY=https://registry.npmjs.org
WORKFLOW=release_node.yml
ENVIRONMENT=npm
PLACEHOLDER=0.0.0-bootstrap.0

name=$(node -p "require('./package.json').name")
repository=$(node -p "require('./package.json').repository.url.replace(/^.*github\.com\//, '').replace(/\.git$/, '')")
packages=("$name")
for dir in npm/*/; do packages+=("${name}-$(basename "$dir")"); done

run() {
  if [ "${DRY_RUN:-}" = 1 ]; then
    echo "+ $*"
  else
    "$@"
  fi
}

if [ "${DRY_RUN:-}" != 1 ]; then
  if ! npm --version | node -e 'const [major, minor] = require("fs").readFileSync(0, "utf8").split(".").map(Number); process.exit(major > 11 || (major === 11 && minor >= 10) ? 0 : 1)'; then
    echo "npm trust needs npm 11.10 or later; this is $(npm --version)" >&2
    exit 1
  fi
  if ! user=$(npm whoami --registry "$REGISTRY" 2>/dev/null); then
    echo "Not logged in to npm: run \`npm login\` first" >&2
    exit 1
  fi
  echo "Logged in as ${user}; configuring ${repository} (${WORKFLOW}, environment ${ENVIRONMENT})"
fi

placeholder=$(mktemp -d)
trap 'rm -rf "$placeholder"' EXIT

for package in "${packages[@]}"; do
  echo
  echo "== ${package}"
  if npm view "$package" name --registry "$REGISTRY" >/dev/null 2>&1; then
    echo "exists on npm"
  else
    cat > "${placeholder}/package.json" <<EOF
{
  "name": "${package}",
  "version": "${PLACEHOLDER}",
  "description": "Placeholder reserving the name for trusted publishing from ${repository}. Install a real version.",
  "repository": { "type": "git", "url": "https://github.com/${repository}.git" },
  "license": "MIT OR Apache-2.0"
}
EOF
    run npm publish "$placeholder" --access public --tag bootstrap --registry "$REGISTRY"
    run npm deprecate "${package}@${PLACEHOLDER}" "Placeholder: install a real version" --registry "$REGISTRY"
  fi
  if [ "${DRY_RUN:-}" != 1 ] && [ "$(npm trust list "$package" --json --registry "$REGISTRY" 2>/dev/null | node -e 'const out = require("fs").readFileSync(0, "utf8").trim(); const list = out ? JSON.parse(out) : []; console.log(Array.isArray(list) ? list.length : 1)')" != 0 ]; then
    echo "already trusts a publisher:"
    npm trust list "$package" --registry "$REGISTRY"
    continue
  fi
  run npm trust github "$package" --file "$WORKFLOW" --repository "$repository" --environment "$ENVIRONMENT" \
    --allow-publish --yes --registry "$REGISTRY"
  # npm's guidance for configuring packages in bulk, to stay clear of its rate limit.
  sleep 2
done

echo
echo "Done. Push a node-v<version> tag to publish over OIDC."
