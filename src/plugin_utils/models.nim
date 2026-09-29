## Data models for Pumpkin plugin licensing, metadata, and marketplace
## endpoints.
## Port of pumpkingmc/crates/pumpkin-plugin-utils/src/models.rs
##
## TODO: `From<pumpkin_plugin_api::MarketplaceMetadata> for PumpkinMetadata`
## is skipped - pumpkin-plugin-api isn't ported. All serde Serialize/
## Deserialize impls are skipped everywhere; JSON (de)serialization for
## `LicenseLease` (the only type that's actually persisted to disk, in
## license.nim) is done by hand there instead of derived here.

const DefaultMarketplaceUrl* = "https://market.pumpkinmc.org"

type
  PumpkinMetadata* = object
    marketplaceUrl*: string
    pluginId*: int64
    pluginName*: string
    version*: string
    devId*: int64
    devName*: string
    isPaid*: bool
    userId*: int64
    licenseKey*: string       ## Empty string stands in for Rust's `Option::None`
    hasLicenseKey*: bool
    issuedAt*: string

  LicenseStatusKind* = enum
    lskValid
    lskGracePeriod
    lskInvalid
    lskUnsigned

  LicenseStatus* = object
    case kind*: LicenseStatusKind
    of lskValid:
      metadata*: PumpkinMetadata
    of lskGracePeriod:
      gpMetadata*: PumpkinMetadata
      daysRemaining*: uint32
      reason*: string
    of lskInvalid:
      invalidReason*: string
    of lskUnsigned:
      discard

  LicenseLease* = object
    pluginName*: string
    licenseKey*: string
    hasLicenseKey*: bool
    status*: string
    lastVerifiedTimestamp*: uint64
    expiresTimestamp*: uint64

  CheckLicenseResponse* = object
    valid*: bool
    status*: string

  CheckUpdateResponse* = object
    updateAvailable*: bool
    latestVersion*: string
    hasLatestVersion*: bool
