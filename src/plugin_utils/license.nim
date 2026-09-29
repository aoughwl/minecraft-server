## License validation, leasing, and offline grace periods.
## Port of pumpkingmc/crates/pumpkin-plugin-utils/src/license.rs
##
## File I/O uses Nimony's actual error mechanism (`try`/`except ErrorCode`,
## per ~/nimony/doc/language.md) rather than the house `PuResult[T]`
## convention, since `readFile`/`writeFile`/`createDir` are stdlib procs
## that already raise `ErrorCode` - there's no custom error data to
## preserve by wrapping them, so no reason not to use Nimony's own
## mechanism here the way it's meant to be used.

import std/[syncio, times, json, dirs, paths, strutils]
import putbase, models, http

type
  LicenseChecker* = object
    dataFolder*: string
    httpClient*: HttpClient

proc newLicenseChecker*(dataFolder: string): LicenseChecker =
  LicenseChecker(dataFolder: dataFolder, httpClient: newHttpClient())

proc leasePath(c: LicenseChecker): string {.inline.} =
  ## `data_folder.join("license_lease.json")`, done by hand since this
  ## crosses OS-specific separators just via a `/` join like upstream's
  ## `Path::join` does.
  if c.dataFolder.len > 0 and c.dataFolder[c.dataFolder.len - 1] == '/':
    c.dataFolder & "license_lease.json"
  else:
    c.dataFolder & "/license_lease.json"

proc leaseToJson(lease: LicenseLease): string =
  ## Hand-rolled rather than derived (no serde-equivalent derive macro in
  ## Nimony); `std/json`'s write side is a low-level cursor/tree API not
  ## meant for building small ad-hoc objects like this one.
  result = "{"
  result.add("\"plugin_name\":\"" & lease.pluginName & "\",")
  if lease.hasLicenseKey:
    result.add("\"license_key\":\"" & lease.licenseKey & "\",")
  else:
    result.add("\"license_key\":null,")
  result.add("\"status\":\"" & lease.status & "\",")
  result.add("\"last_verified_timestamp\":" & $lease.lastVerifiedTimestamp & ",")
  result.add("\"expires_timestamp\":" & $lease.expiresTimestamp)
  result.add("}")

proc leaseFromJson(data: string): PuResult[LicenseLease] =
  var tree = parseJson(data)
  if hasError(tree):
    return errRes[LicenseLease](puError(pekJson, errorMsg(tree)))
  let keyNode = tree{"license_key"}
  var lease = LicenseLease(
    pluginName: getStr(tree{"plugin_name"}),
    status: getStr(tree{"status"}),
    lastVerifiedTimestamp: uint64(getInt(tree{"last_verified_timestamp"})),
    expiresTimestamp: uint64(getInt(tree{"expires_timestamp"})),
  )
  if kind(keyNode) == JString:
    lease.licenseKey = getStr(keyNode)
    lease.hasLicenseKey = true
  ok[LicenseLease](lease)

proc readCachedLease*(c: LicenseChecker): PuResult[LicenseLease] =
  ## `None` in Rust (missing file, unreadable, or unparsable) becomes an
  ## error result here rather than a bool-tagged optional, so the reason
  ## isn't lost - callers that just want the Option behavior can check
  ## `.isOk`.
  var content: string
  try:
    content = readFile(c.leasePath())
  except ErrorCode:
    return errRes[LicenseLease](puError(pekIo, "no cached lease file"))
  leaseFromJson(content)

proc writeCachedLease*(c: LicenseChecker, lease: LicenseLease): PuVoidResult =
  try:
    createDir(path(c.dataFolder))
  except ErrorCode:
    return errVoid(puError(pekIo, "failed to create data folder " & c.dataFolder))
  try:
    writeFile(c.leasePath(), leaseToJson(lease))
  except ErrorCode:
    return errVoid(puError(pekIo, "failed to write lease file"))
  okVoid()

proc currentTimestamp(): uint64 =
  uint64(toUnix(getTime()))

proc evaluateLicense*(c: LicenseChecker, metadata: PumpkinMetadata,
                       gracePeriodDays: uint32): LicenseStatus =
  if not metadata.isPaid:
    return LicenseStatus(kind: lskValid, metadata: metadata)

  if not metadata.hasLicenseKey:
    return LicenseStatus(kind: lskInvalid,
      invalidReason: "Paid plugin metadata is missing a license_key")

  let now = currentTimestamp()
  let leaseRes = readCachedLease(c)
  if leaseRes.isOk:
    let lease = leaseRes.value
    # `eq_ignore_ascii_case` - compare case-insensitively on ASCII only.
    if toLowerAscii(lease.pluginName) == toLowerAscii(metadata.pluginName) and
       lease.status == "valid" and now <= lease.expiresTimestamp:
      return LicenseStatus(kind: lskValid, metadata: metadata)

    let graceSeconds = uint64(gracePeriodDays) * 86400'u64
    if now <= lease.lastVerifiedTimestamp + graceSeconds:
      let deadline = lease.lastVerifiedTimestamp + graceSeconds
      let secondsLeft = if deadline > now: deadline - now else: 0'u64
      var daysRemaining = uint32(secondsLeft div 86400'u64)
      if daysRemaining < 1'u32:
        daysRemaining = 1'u32
      return LicenseStatus(kind: lskGracePeriod, gpMetadata: metadata,
        daysRemaining: daysRemaining,
        reason: "Operating in offline grace period with previous valid lease")

  # No cached lease yet (first run) and offline: allow initial valid state.
  LicenseStatus(kind: lskValid, metadata: metadata)

proc checkLicenseOnline*(c: LicenseChecker, metadata: PumpkinMetadata,
                          licenseKeyOverride: string,
                          hasOverride: bool): PuResult[CheckLicenseResponse] =
  var licenseKey: string
  if hasOverride:
    licenseKey = licenseKeyOverride
  elif metadata.hasLicenseKey:
    licenseKey = metadata.licenseKey
  else:
    return errRes[CheckLicenseResponse](
      puError(pekMetadataMismatch, "No license key available in metadata or argument"))

  var base = metadata.marketplaceUrl
  while base.len > 0 and base[base.len - 1] == '/':
    base.setLen(base.len - 1)
  let url = base & "/api/v1/rest/check-license?plugin_name=" &
    urlencoding(metadata.pluginName) & "&license_key=" & urlencoding(licenseKey)

  let bodyRes = c.httpClient.get(url)
  if not bodyRes.isOk:
    return errRes[CheckLicenseResponse](bodyRes.error)

  # TODO: parse bodyRes.value into CheckLicenseResponse (same JSON-parsing
  # gap as updater.nim) and persist the resulting lease via
  # writeCachedLease, once http.nim has a real client to test this against.
  errRes[CheckLicenseResponse](puError(pekNotImplemented,
    "response JSON parsing not wired up yet"))
