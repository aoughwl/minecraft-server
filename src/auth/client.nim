## HTTP client utilities.
## Port of pumpkingmc/crates/pumpkin-auth/src/client.rs
##
## Rust's `client()`/`client_builder()` build a `reqwest::Client` with
## `rustls` TLS and (on Android) a bundled Mozilla root-cert store. This is
## pure glue over Rust's HTTP/TLS ecosystem crates (reqwest, rustls,
## webpki-root-certs) with no Nimony stdlib equivalent (checked
## ~/nimony/lib/std/ - no HTTP client, no TLS). Skipped entirely: there is
## nothing here to mechanically translate until a Nimony HTTP+TLS client
## exists to build on. Whatever ends up doing outbound HTTPS for this
## server (Mojang session-server calls, etc.) will need that dependency
## solved first, independent of this crate's port.
