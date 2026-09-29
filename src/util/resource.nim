## Port of pumpkingmc/crates/pumpkin-util/src/resource.rs

import identifier

type
  ResourceKey* = object
    registryName*: Identifier
    identifier*: Identifier

proc newResourceKey*(registryName, identifier: Identifier): ResourceKey =
  ResourceKey(registryName: registryName, identifier: identifier)

proc castKey*(key: ResourceKey, registry: Identifier): (bool, ResourceKey) =
  ## Port of `ResourceKey::cast`, which returns `Option<&Self>`. Named
  ## `castKey` since `cast` is a reserved builtin in Nimony/Nim.
  if key.registryName == registry:
    (true, key)
  else:
    (false, key)
