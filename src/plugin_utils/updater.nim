## Non-blocking update checks against the marketplace
## `/api/v1/rest/check-update` endpoint.
## Port of upstream/plugin-utils/src/updater.rs
##
## TODO: JSON *parsing* of the response (`serde_json::from_str::<CheckUpdateResponse>`)
## isn't wired up yet - `std/json` exists in Nimony and this is straightforward
## once http.nim has a real client to fetch a body from; not worth doing
## against untestable dead code first.

import putbase, http, models

type
  UpdateChecker* = object
    httpClient*: HttpClient

proc newUpdateChecker*(): UpdateChecker =
  UpdateChecker(httpClient: newHttpClient())

proc checkForUpdates*(u: UpdateChecker, pluginName, currentVersionStr,
                       marketplaceUrl: string): PuResult[CheckUpdateResponse] =
  ## `GET /api/v1/rest/check-update?plugin_name={name}&current_version={version}`
  var base = marketplaceUrl
  while base.len > 0 and base[base.len - 1] == '/':
    base.setLen(base.len - 1)
  let url = base & "/api/v1/rest/check-update?plugin_name=" & urlencoding(pluginName) &
    "&current_version=" & urlencoding(currentVersionStr)

  let bodyRes = u.httpClient.get(url)
  if not bodyRes.isOk:
    return errRes[CheckUpdateResponse](bodyRes.error)
  # TODO: parse bodyRes.value as JSON into CheckUpdateResponse once http.nim
  # actually returns a body.
  errRes[CheckUpdateResponse](puError(pekNotImplemented,
    "response JSON parsing not wired up yet"))
