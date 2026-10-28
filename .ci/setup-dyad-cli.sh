#!/usr/bin/env bash
set -euo pipefail

expected_version=3.5.1
install_dir=$(mktemp -d "${RUNNER_TEMP:?}/dyad-cli.XXXXXX")

# The self-hosted runner needs gh credentials with access to dyad-lang,
# just as the former compiler source build needed private repository access.
gh release download "v${expected_version}" \
    --repo JuliaComputing/dyad-lang \
    --pattern dyad-linux-x64 \
    --pattern SHA256SUMS.txt \
    --dir "$install_dir"
(
    cd "$install_dir"
    sha256sum --check --strict --ignore-missing SHA256SUMS.txt
)
mv "$install_dir/dyad-linux-x64" "$install_dir/dyad"
chmod +x "$install_dir/dyad"

version=$("$install_dir/dyad" --version)
printf 'Installed Dyad CLI: %s\n' "$version"
if [[ "${version%% *}" != "$expected_version" ]]; then
    printf 'Expected Dyad CLI %s, found %s\n' "$expected_version" "$version" >&2
    exit 1
fi

# Only expose the verified binary; never fall back to the runner's CLI.
printf 'DYAD_CLI_PATH=%s/dyad\n' "$install_dir" >> "${GITHUB_ENV:?}"
printf '%s\n' "$install_dir" >> "${GITHUB_PATH:?}"
