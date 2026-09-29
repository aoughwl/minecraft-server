## Port of upstream/pumpkin/src/entity/experience_orb.rs:
## `ExperienceOrbEntity`, a second concrete `EntityBase` implementor with
## real (not just constant) per-instance state and one genuinely portable
## pure function (`roundToOrbSize`).

import entity
import ../../nbt/tag

type
  ExperienceOrbEntity* = ref object
    entity*: Entity
    amount*: uint32
    orbAge*: uint32

proc roundToOrbSize*(value: uint32): uint32 =
  ## Port of `ExperienceOrbEntity::round_to_orb_size` - splits an XP amount
  ## into the largest single orb size Minecraft actually spawns (mirrors
  ## vanilla's greedy orb-splitting table). Pure, fully portable, and the
  ## one piece of this file's logic worth verifying by value rather than
  ## just by inspection - see experienceorbtest.nim.
  if value >= 2477: 2477'u32
  elif value >= 1237: 1237'u32
  elif value >= 617: 617'u32
  elif value >= 307: 307'u32
  elif value >= 149: 149'u32
  elif value >= 73: 73'u32
  elif value >= 37: 37'u32
  elif value >= 17: 17'u32
  elif value >= 7: 7'u32
  elif value >= 3: 3'u32
  else: 1'u32

proc newExperienceOrbEntity*(e: Entity, amount: uint32): ExperienceOrbEntity =
  ## Port of `ExperienceOrbEntity::new`. Upstream also randomizes
  ## `entity.yaw` on construction (`rand::random::<f32>() * 360.0`) - no
  ## RNG is wired to entity construction yet (src/util/'s PRNGs are
  ## ported and verified, but nothing here owns a world seed/rng instance
  ## to draw from), so `yaw` is left at `Entity`'s default. TODO once a
  ## world-level RNG exists.
  ExperienceOrbEntity(entity: e, amount: amount, orbAge: 0)

proc experienceOrbBaseOf*(orb: ExperienceOrbEntity): EntityBase =
  ## Port of `impl EntityBase for ExperienceOrbEntity`. Upstream's `tick`
  ## does real physics (gravity, `move_entity`, block-collision, despawn
  ## at age >= 6000) and `on_player_collision` does real pickup/XP-application
  ## logic - both need `World`/`Player.experiencePickUpDelay`/
  ## `applyMendingFromXp`, none of which exist yet (blocker #1 in
  ## src/server/block/README.md, still open). Both are left as documented
  ## no-ops/TODOs rather than faked; the despawn-age check is the one piece
  ## of `tick` that's pure state and IS ported for real.
  EntityBase(
    kind: ekEntity,
    getEntityImpl: (proc(): Entity {.closure.} = orb.entity),
    getLivingEntityImpl: (proc(): nil LivingEntity {.closure.} = nil),
    getPlayerImpl: (proc(): nil Player {.closure.} = nil),
    tickImpl: (proc(caller: EntityBase) {.closure.} =
      # TODO: gravity/velocity/move_entity/tick_block_collisions all need
      # World, which doesn't exist yet.
      inc orb.orbAge
      if orb.orbAge >= 6000'u32:
        remove(orb.entity)),
    writeCustomNbtImpl: (proc(nbt: var NbtCompound) {.closure.} = discard),
    readCustomNbtImpl: (proc(nbt: NbtCompound) {.closure.} = discard),
    damageImpl: (proc(caller: EntityBase, amount: float32, dtype: DamageType): bool {.closure.} = false),
  )

# `on_player_collision` (real pickup/experience logic) and `spawn`
# (splits a total XP amount into orb-sized chunks via roundToOrbSize and
# spawns one entity per chunk into a World) both need World/Player types
# that don't exist yet - documented TODOs, not ported.
