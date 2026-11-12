# entity/ (pumpkin/src/entity)

`entitymod.aowl` holds `Entity`, `EntityBase`, `LivingEntity` and the entity half of `World`: the trait is a `ref object` with a `vt` of closures, and a concrete entity derives from `EntityBase`, with `vt` from `copyVt(entityVt())` or `copyVt(livingVt())`. How to write one is at the top of that file. `ai/aibase.aowl` is the same for `Mob` and `Goal`; `ai/goal` has the goals, and `ai/pathfinder` has the navigator.

| File | Upstream |
| --- | --- |
| `entitymod.aowl` | `mod.rs`, `living.rs`, `effect/mod.rs`, entity half of `world/mod.rs` |
| `attributes.aowl`, `combat.aowl`, `hunger.aowl`, `breath.aowl`, `ageable.aowl` | files of those names |
| `falling.aowl`, `tnt.aowl`, `itementity.aowl`, `experienceorb.aowl`, `area_effect_cloud.aowl` | `falling/`, `tnt.rs`, `item.rs`, `experience_orb.rs`, `area_effect_cloud.rs` |
| `predicate.aowl`, `projectile_deflection.aowl`, `raycast.aowl`, `entitytype.aowl` | `predicate/`, `projectile_deflection.rs`, `World::raycast`, `type.rs` |
| `projectile/thrown.aowl`, `thrown_items.aowl`, `arrow.aowl`, `bobber_bullet.aowl`, `projectilesmod.aowl` | `projectile/*` |
| `ai/aibase.aowl`, `ai/goal/*`, `ai/pathfinder/*` | `ai/*`, `mob/mod.rs` |
| `respawn.aowl`, `playerattack.aowl` | `player.rs`: `calculate_respawn_point` and what it calls; `attack` |
| `mob/`, `passive/`, `boss/`, `vehicle/`, `decoration/`, `player.aowl`, `player/` | those |

`entity.aowl` is older than all of this, and has no tie to the rest. It is still used by tests in `src/server/command`; `entitytest.aowl` is its test.

## Hooks

`gBlockHooks`, `gPlayerHooks`, `gDropStack`, `gScatterStack`, `gSpawnExperienceOrb`, `gFromType`, `gLootHook`, `gEatHook` and `gDrinkPotionHook` in `entitymod.aowl`, and `gEquipMobOnSpawn`, `gGetSkyLightLevel` and `gGetBlockLightLevel` in `ai/aibase.aowl`, are what these modules ask of code above them. World does not tick entities by itself: the server tick must call `tickEntities(world, server)`.

## What the server wires (block/worldhooks.aowl)

`installBlockHooks` fills, per world, `tickEntitiesHook` (`tickEntities`), `playerJoinedHook` (`sendEntitiesTo`) and `shutdownHook` (`saveAllEntities`, run by `worldmod.shutdown`). At module level it fills `gBlockHooks.onEntityCollision` and `onEntityStep` (the block registry), `gPlayerHooks.incrementStat`, `setStat` and `handleKilled`, and the hooks player.aowl and worldmod.aowl keep for what sits above them: `gDropItemHook`, `gFallHook`, `gPlayerKillHook`, `gPlayerDamageHook`, `gCalculateRespawnHook`, `gPlayerRespawnedHook`. A player's share of `LivingEntity::tick` (entity tick, block collisions, effects, hurt cooldown, breath, hunger) is `playerLivingTick`, chained after `tickPlayerPortals` on `gPlayerEntityTickHook`. Still no backing: `gBlockHooks.onEntityCollisionFluid` and `onLandedUpon`, `gPlayerHooks.triggerAdvancement`, `startCooldown`, `getSupportingBlockPos`, `applyMendingFromXp`.
