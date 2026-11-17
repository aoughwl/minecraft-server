# Phase 3 #20: one-click hosting, relay / NAT punch-through, friends and invites

## Shipped (tested, `src/server/net/hosting/hostingtest.aowl`; glue `src/plugin/invitecmd.aowl`)

All pure bytes/strings, no sockets.

* **Invite codes** (`invite.aowl`): version/kind byte, host (IPv4 4 bytes, IPv6 16 bytes or relay room 8 bytes), port u16, 4-byte
  token, CRC-16/CCITT-FALSE, Crockford base32 in groups of 5 (`230AG-08MCF-EXXBD-YXZAF-8` = 192.168.1.20:25565). Decoder accepts
  lower case, missing dashes and O/I/L look-alikes, rejects bad characters, extra characters, wrong length, wrong version/kind.
  Proof: known answers computed with an independent implementation (CRC check value 0x29B1, base32 "foobar" -> CSQPYRK1E8) and
  all 21 x 31 single-character typos of a code are rejected.
* **NAT-PMP** (`natpmp.aowl`, RFC 6886): external-address and TCP/UDP map/delete requests, reply parser, result texts, the
  250 ms doubling retry schedule. Byte-exact against hand-written RFC frames.
* **UPnP IGD** (`upnp.aowl`): SSDP M-SEARCH, 200 OK LOCATION parse, description-XML controlURL lookup for WANIPConnection /
  WANPPPConnection, URL join, SOAP AddPortMapping / DeletePortMapping / GetExternalIPAddress bodies, SOAPAction header, error
  code parse (718, 725 ...).
* **`/invite <ipv4> <port>`** and **`/invite decode <code>`** (op level 0 = anyone; registered in `pluginmgr.startPlugins`).
  INCONCLUSIVE in a live server: only typechecked (`aowlmony check` exit 0), no whole-server build was run (see PROGRESS.md).
  The token is a placeholder hash of address+port, **not a secret**.

## Not done, and exactly what is left

1. **The I/O loops (needs a router to prove, so not unit-testable).**
   * NAT-PMP: UDP to the default gateway:5351 (gateway address from the OS routing table: `GetBestRoute`/`GetAdaptersAddresses`
     through winsock glue in `net/winsock.aowl`), send external-address request, then map TCP `<port>` with lifetime 7200 and
     renew at half life, delete on `stop`. Use `retryDelayMs`.
   * UPnP: UDP multicast 239.255.255.250:1900 send `ssdpSearchRequest`, 3 s window, GET LOCATION over plain HTTP (the `requests`
     module or raw winsock), `findControlUrl`/`joinUrl`, POST SOAP with the headers `Content-Type: text/xml`, `SOAPAction`.
     Internal client address = the local address of the socket that reached the gateway. Always remove the mapping on stop
     (a crashed server leaves it until the lease ends, so use a lease, not 0).
   * Result: the server learns its public address and a mapped port; `/invite` then needs no arguments. A hosting status line
     goes in `/hosting status`. Try NAT-PMP first, then UPnP; tell the user clearly when both fail (CGNAT: external address is
     private, 100.64.0.0/10 or 10/8: the router address differs from what the gateway reports).
2. **Relay and punch-through: needs a service, so needs user approval.** Design: a small relay server (own box or cloud) that
   speaks Minecraft's handshake transparently: the host opens an outbound TCP "control" connection and registers a room id
   (the relay-kind invite carries the 8-byte room id; the relay address is built into the client/launcher config, not the code);
   the relay forwards each guest TCP connection by asking the host to open a data connection tagged with the guest id. This works
   behind CGNAT. True UDP hole punching does not apply to Minecraft Java (TCP); TCP simultaneous-open punching is unreliable, so
   the relay is the real fallback. Needs: someone to operate it, abuse/bandwidth limits, auth of room registration (use the token
   as an HMAC key), and the user's decision on hosting cost and privacy (a relay sees all traffic metadata; Java traffic is
   unencrypted before login unless online-mode, so say so).
3. **Friends.** Needs an identity source: Mojang/Microsoft profile (already in `auth/`) or the launcher's own account. Plan: friends
   list stored in the launcher (aoughwl.mcserver), invite = code + the friend's UUID added to the whitelist through the existing
   whitelist/ops files, join guard compares the token. Server side only needs a `/invite <player>` that adds to the whitelist and
   sends the chat message; it was not built (needs the whitelist API reading and a live test).
4. **Launcher one-click (Jester mod `aoughwl.mcserver`).** Not changed in this session (game rebuild rules: check processes first;
   no changes needed to test the codecs). Work: a "Host for friends" button in the mod's UI that sets a `share = upnp|natpmp|off`
   line in `host.txt`, passes it to the server through its config/env, shows the status and the invite code from the server's
   `/invite` output (RCON), and a copy-to-clipboard action. Build with `jester_mod build` only when the game is not running.
5. **Security.** Opening a port exposes the server to the internet: require online-mode or a whitelist when sharing is on, rate-limit
   logins, and show the user what is exposed. Needs user approval of the default.
