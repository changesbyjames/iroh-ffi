#!/usr/bin/env bash
# Make every package the release workflow publishes trust it, so releases publish over OIDC with no stored token.
#
# npm can only trust a workflow for a package that already exists. So each package that is not on npm yet is first
# reserved with a placeholder version (under the `bootstrap` dist-tag, deprecated), then trusts
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
# A publish that never completed its two-factor check can still hold its version (`Cannot publish over previously
# staged version`): set PLACEHOLDER to another one to get past it.
PLACEHOLDER=${PLACEHOLDER:-0.0.0-bootstrap.1}

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

# The registry's answer for a package, or one of its versions, past npm's CDN cache: 200 once it is visible.
visible() {
  curl -s -o /dev/null -w '%{http_code}' -H 'Cache-Control: no-cache' "${REGISTRY}/${1/\//%2f}${2:+/$2}"
}

placeholder=$(mktemp -d)
trap 'rm -rf "$placeholder"' EXIT

# Publish every missing placeholder first, so they all fall in one two-factor window. npm creates a new package with
# its own 0.0.0-stage version, and the placeholder only becomes visible a minute or two later.
published=()
for package in "${packages[@]}"; do
  echo
  echo "== ${package}"
  if [ "$(visible "$package")" = 200 ]; then
    echo "exists on npm"
    continue
  fi
  cat > "${placeholder}/package.json" <<EOF
{
  "name": "${package}",
  "version": "${PLACEHOLDER}",
  "description": "Placeholder reserving the name for trusted publishing from ${repository}. Install a real version.",
  "repository": { "type": "git", "url": "git+https://github.com/${repository}.git" },
  "license": "MIT OR Apache-2.0"
}
EOF
  # npm's output stays on the terminal: piped, npm cannot open the browser for two-factor authentication.
  if ! run npm publish "$placeholder" --access public --tag bootstrap --registry "$REGISTRY"; then
    # A publish still being processed refuses another of the same version. If the package has appeared since, the
    # earlier publish arrived; otherwise this one failed.
    if [ "$(visible "$package")" != 200 ]; then
      echo "Publishing ${package} failed" >&2
      exit 1
    fi
    echo "already published, still being processed"
  fi
  published+=("$package")
done

if [ "${DRY_RUN:-}" != 1 ]; then
  for package in "${published[@]+"${published[@]}"}"; do
    printf '\nWaiting for %s@%s to become visible' "$package" "$PLACEHOLDER"
    for _ in $(seq 60); do
      [ "$(visible "$package" "$PLACEHOLDER")" = 200 ] && break
      printf .
      sleep 10
    done
    if [ "$(visible "$package" "$PLACEHOLDER")" != 200 ]; then
      printf '\n%s@%s is still not visible after 10 minutes: run this again later\n' "$package" "$PLACEHOLDER" >&2
      exit 1
    fi
  done
  echo
fi

for package in "${packages[@]}"; do
  echo
  echo "== trust: ${package}"
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

# Cosmetic: a placeholder left undeprecated does no harm, so failing here only warns.
for package in "${packages[@]}"; do
  if [ "${DRY_RUN:-}" = 1 ]; then
    run npm deprecate "${package}@${PLACEHOLDER}" "Placeholder: install a real version" --registry "$REGISTRY"
    continue
  fi
  versions=$(curl -s -H 'Cache-Control: no-cache' "${REGISTRY}/${package/\//%2f}" | node -e '
    let text = "";
    process.stdin.on("data", chunk => (text += chunk)).on("end", () => {
      const versions = JSON.parse(text).versions ?? {};
      for (const [version, manifest] of Object.entries(versions))
        if (version.startsWith("0.0.0-bootstrap.") && !manifest.deprecated) console.log(version);
    });
  ')
  for version in $versions; do
    npm deprecate "${package}@${version}" "Placeholder: install a real version" --registry "$REGISTRY" ||
      echo "warning: could not deprecate ${package}@${version}" >&2
  done
done

echo
echo "Done. Push a node-v<version> tag to publish over OIDC."
