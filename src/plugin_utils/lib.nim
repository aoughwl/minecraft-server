## Plugin utilities - module index and global plugin state.
## Port of upstream/plugin-utils/src/lib.rs
##
## Rust caches metadata in a `static OnceLock`, set once from a WASM guest's
## `Context` (via `plugin_api`, not ported) or explicitly via
## `init_with_metadata` for tests/host-side use. `init(context)` itself -
## the WASM-guest path that reads `context.get_marketplace_metadata()` - is
## skipped entirely: it needs plugin-api's `Context`/
## `MarketplaceMetadata` types and the wasm32-vs-native `cfg` split, neither
## of which exists here yet. `init_with_metadata`, `get_metadata`,
## `metadata`, `get_data_folder`, and the three convenience wrappers below
## are all host-side logic and port cleanly.
##
## Nimony has no `OnceLock`/thread-safe lazy-static primitive in its stdlib;
## this single-plugin-per-process port uses plain global `var`s guarded by
## a `hasX` bool, matching the `Option`-via-tuple pattern used elsewhere in
## this port. Not thread-safe - neither is a straight port of `OnceLock`
## without its actual synchronization, so this doesn't regress anything,
## just doesn't yet add real thread-safety either. TODO if/when plugins run
## on multiple threads.

import putbase, models, license, updater

export models, license, updater

var
  globalMetadata: ServerMetadata
  hasGlobalMetadata = false
  globalDataFolder: string
  hasGlobalDataFolder = false

proc initWithMetadata*(metadata: sink ServerMetadata, dataFolder: string): PuResult[ServerMetadata] =
  ## Rust's version only *sets* a `OnceLock` once (later calls are no-ops
  ## that still return the original value); this port simply overwrites,
  ## since there's no lock-set-once primitive to mirror faithfully without
  ## adding one from scratch for a single-plugin-per-process port. Revisit
  ## if multiple `init`/`init_with_metadata` calls per process become real.
  globalDataFolder = dataFolder
  hasGlobalDataFolder = true
  globalMetadata = metadata
  hasGlobalMetadata = true
  ok[ServerMetadata](globalMetadata)

proc getMetadata*(): PuResult[ServerMetadata] =
  if hasGlobalMetadata:
    ok[ServerMetadata](globalMetadata)
  else:
    errRes[ServerMetadata](notInitializedErr())

proc metadata*(): PuResult[ServerMetadata] =
  getMetadata()

proc getDataFolder*(): PuResult[string] =
  if hasGlobalDataFolder:
    ok[string](globalDataFolder)
  else:
    errRes[string](notInitializedErr())

proc checkLicenseOnline*(licenseKeyOverride: string, hasOverride: bool): PuResult[CheckLicenseResponse] =
  let metaRes = getMetadata()
  if not metaRes.isOk:
    return errRes[CheckLicenseResponse](metaRes.error)
  let folderRes = getDataFolder()
  if not folderRes.isOk:
    return errRes[CheckLicenseResponse](folderRes.error)
  let checker = newLicenseChecker(folderRes.value)
  checkLicenseOnline(checker, metaRes.value, licenseKeyOverride, hasOverride)

proc checkForUpdates*(): PuResult[CheckUpdateResponse] =
  let metaRes = getMetadata()
  if not metaRes.isOk:
    return errRes[CheckUpdateResponse](metaRes.error)
  let meta = metaRes.value
  let checker = newUpdateChecker()
  checkForUpdates(checker, meta.pluginName, meta.version, meta.marketplaceUrl)

proc evaluateLicense*(gracePeriodDays: uint32): LicenseStatus =
  if not hasGlobalDataFolder or not hasGlobalMetadata:
    return LicenseStatus(kind: lskInvalid,
      invalidReason: "plugin_utils has not been initialized")
  let checker = newLicenseChecker(globalDataFolder)
  evaluateLicense(checker, globalMetadata, gracePeriodDays)
