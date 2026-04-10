#!/usr/bin/env bash
# Release the gpu-operator Helm chart as a GitHub Release asset.
#
# Usage:
#   ./scripts/release-chart.sh <version> [<upstream-branch>]
#
# Example:
#   ./scripts/release-chart.sh v24.9.0-castai1
#   ./scripts/release-chart.sh v24.9.0-castai1 release-v24.9
#
# When an upstream branch is supplied, it is fetched from the NVIDIA upstream
# remote and checked out into a temporary worktree for packaging — your working
# tree is not touched.
#
# The chart .tgz is uploaded to a GitHub Release tagged <version>.
# Install later with:
#   helm install gpu-operator \
#     https://github.com/castai/gpu-operator/releases/download/<version>/gpu-operator-<version>.tgz

set -euo pipefail

VERSION="${1:-}"
UPSTREAM_BRANCH="${2:-}"

if [[ -z "${VERSION}" ]]; then
  echo "Usage: $0 <version> [<upstream-branch>]  (e.g. v24.9.0-castai1 release-v24.9)" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"
GITHUB_REPO="castai/gpu-operator"
UPSTREAM_REMOTE="upstream"
UPSTREAM_URL="https://github.com/NVIDIA/gpu-operator.git"

command -v helm >/dev/null 2>&1 || { echo "helm not found" >&2; exit 1; }
command -v gh   >/dev/null 2>&1 || { echo "gh not found" >&2;   exit 1; }

# If an upstream branch is requested, check it out to a temp worktree
WORKTREE_DIR=""
if [[ -n "${UPSTREAM_BRANCH}" ]]; then
  # Ensure upstream remote exists
  if ! git -C "${REPO_ROOT}" remote get-url "${UPSTREAM_REMOTE}" >/dev/null 2>&1; then
    echo "Adding upstream remote: ${UPSTREAM_URL}"
    git -C "${REPO_ROOT}" remote add "${UPSTREAM_REMOTE}" "${UPSTREAM_URL}"
  fi

  echo "Fetching ${UPSTREAM_REMOTE}/${UPSTREAM_BRANCH} ..."
  git -C "${REPO_ROOT}" fetch "${UPSTREAM_REMOTE}" "${UPSTREAM_BRANCH}"

  WORKTREE_DIR="$(mktemp -d)"
  trap 'git -C "${REPO_ROOT}" worktree remove --force "${WORKTREE_DIR}" 2>/dev/null || rm -rf "${WORKTREE_DIR}"' EXIT
  git -C "${REPO_ROOT}" worktree add --detach "${WORKTREE_DIR}" "FETCH_HEAD"
  echo "Checked out ${UPSTREAM_BRANCH} into ${WORKTREE_DIR}"
  CHART_DIR="${WORKTREE_DIR}/deployments/gpu-operator"
else
  CHART_DIR="${REPO_ROOT}/deployments/gpu-operator"
fi

# Update Chart.yaml version fields
sed -i.bak \
  -e "s/^version:.*$/version: ${VERSION}/" \
  -e "s/^appVersion:.*$/appVersion: \"${VERSION}\"/" \
  "${CHART_DIR}/Chart.yaml"
rm -f "${CHART_DIR}/Chart.yaml.bak"

echo "Updating dependencies..."
helm dependency update "${CHART_DIR}"

mkdir -p "${DIST_DIR}"
echo "Packaging chart..."
helm package "${CHART_DIR}" --destination "${DIST_DIR}" --version "${VERSION}" --app-version "${VERSION}"

PACKAGE="${DIST_DIR}/gpu-operator-${VERSION}.tgz"
[[ -f "${PACKAGE}" ]] || { echo "Package not found: ${PACKAGE}" >&2; exit 1; }

echo "Creating GitHub Release ${VERSION}..."
gh release create "${VERSION}" "${PACKAGE}" \
  --repo "${GITHUB_REPO}" \
  --title "gpu-operator ${VERSION}" \
  --notes "Helm chart ${VERSION}

\`\`\`bash
helm install gpu-operator \\
  https://github.com/castai/gpu-operator/releases/download/${VERSION}/gpu-operator-${VERSION}.tgz
\`\`\`"

echo ""
echo "Done. Install with:"
echo "  helm install gpu-operator \\"
echo "    https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/gpu-operator-${VERSION}.tgz"