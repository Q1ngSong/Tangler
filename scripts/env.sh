# Shared build settings. Source from a script that has set ROOT; do not run directly.
: "${ROOT:?set ROOT before sourcing env.sh}"

# Keep each source checkout in an independent build cache. Override
# TANGLER_BUILD_ROOT to choose another cache location.
CHECKOUT_ID=$(print -r -- "$ROOT" | shasum | cut -c1-10)
BUILD_ROOT="${TANGLER_BUILD_ROOT:-/private/tmp/tangler-build-$CHECKOUT_ID}"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swift-cache"
SWIFTPM_PATHS=(--disable-sandbox
  --scratch-path "$BUILD_ROOT/artifacts" --cache-path "$BUILD_ROOT/cache"
  --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security")

