## Generated from upstream's worldgen/biome datapack JSON.
## Port of upstream/tools/pumpkin-codegen/src/biome.rs (climate fields only - see gen_biome.nim).

type Biome* = object
  name*: string
  hasPrecipitation*: bool
  temperature*: float32
  downfall*: float32
  temperatureModifier*: string
  carvers*: seq[string]
  features*: seq[string]

let BADLANDS* = Biome(
  name: "minecraft:badlands",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:ore_gold_extra", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_grass_badlands", "minecraft:patch_dry_grass_badlands", "minecraft:patch_dead_bush_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_sugar_cane_badlands", "minecraft:patch_pumpkin", "minecraft:patch_cactus_decorated", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let BAMBOO_JUNGLE* = Biome(
  name: "minecraft:bamboo_jungle",
  hasPrecipitation: true,
  temperature: 0.95'f32,
  downfall: 0.9'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:bamboo", "minecraft:bamboo_vegetation", "minecraft:flower_warm", "minecraft:patch_grass_jungle", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:vines", "minecraft:patch_melon", "minecraft:freeze_top_layer"],
)

let BASALT_DELTAS* = Biome(
  name: "minecraft:basalt_deltas",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:nether_cave"],
  features: @["minecraft:delta", "minecraft:small_basalt_columns", "minecraft:large_basalt_columns", "minecraft:basalt_blobs", "minecraft:blackstone_blobs", "minecraft:spring_delta", "minecraft:patch_fire", "minecraft:patch_soul_fire", "minecraft:glowstone_extra", "minecraft:glowstone", "minecraft:brown_mushroom_nether", "minecraft:red_mushroom_nether", "minecraft:ore_magma", "minecraft:spring_closed_double", "minecraft:ore_gold_deltas", "minecraft:ore_quartz_deltas", "minecraft:ore_ancient_debris_large", "minecraft:ore_debris_small"],
)

let BEACH* = Biome(
  name: "minecraft:beach",
  hasPrecipitation: true,
  temperature: 0.8'f32,
  downfall: 0.4'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let BIRCH_FOREST* = Biome(
  name: "minecraft:birch_forest",
  hasPrecipitation: true,
  temperature: 0.6'f32,
  downfall: 0.6'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:forest_flowers", "minecraft:wildflowers_birch_forest", "minecraft:trees_birch", "minecraft:patch_bush", "minecraft:flower_default", "minecraft:patch_grass_forest", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let CHERRY_GROVE* = Biome(
  name: "minecraft:cherry_grove",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:ore_emerald", "minecraft:ore_infested", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_tall_grass_2", "minecraft:patch_grass_plain", "minecraft:flower_cherry", "minecraft:trees_cherry", "minecraft:freeze_top_layer"],
)

let COLD_OCEAN* = Biome(
  name: "minecraft:cold_ocean",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:seagrass_cold", "minecraft:kelp_cold", "minecraft:freeze_top_layer"],
)

let CRIMSON_FOREST* = Biome(
  name: "minecraft:crimson_forest",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:nether_cave"],
  features: @["minecraft:spring_open", "minecraft:patch_fire", "minecraft:glowstone_extra", "minecraft:glowstone", "minecraft:ore_magma", "minecraft:spring_closed", "minecraft:ore_gravel_nether", "minecraft:ore_blackstone", "minecraft:ore_gold_nether", "minecraft:ore_quartz_nether", "minecraft:ore_ancient_debris_large", "minecraft:ore_debris_small", "minecraft:spring_lava", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:weeping_vines", "minecraft:crimson_fungi", "minecraft:crimson_forest_vegetation"],
)

let DAPPLED_FOREST* = Biome(
  name: "minecraft:dappled_forest",
  hasPrecipitation: true,
  temperature: 0.6'f32,
  downfall: 0.6'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_dappled_forest", "minecraft:brown_mushroom_dappled_forest", "minecraft:patch_red_shrub", "minecraft:patch_grass_forest", "minecraft:freeze_top_layer"],
)

let DARK_FOREST* = Biome(
  name: "minecraft:dark_forest",
  hasPrecipitation: true,
  temperature: 0.7'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:dark_forest_vegetation", "minecraft:forest_flowers", "minecraft:flower_default", "minecraft:patch_grass_forest", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_leaf_litter", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let DEEP_COLD_OCEAN* = Biome(
  name: "minecraft:deep_cold_ocean",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:seagrass_deep_cold", "minecraft:kelp_cold", "minecraft:freeze_top_layer"],
)

let DEEP_DARK* = Biome(
  name: "minecraft:deep_dark",
  hasPrecipitation: true,
  temperature: 0.8'f32,
  downfall: 0.4'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:sculk_vein", "minecraft:sculk_patch_deep_dark", "minecraft:glow_lichen", "minecraft:patch_tall_grass_2", "minecraft:trees_plains", "minecraft:flower_plains", "minecraft:patch_grass_plain", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:freeze_top_layer"],
)

let DEEP_FROZEN_OCEAN* = Biome(
  name: "minecraft:deep_frozen_ocean",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "frozen",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:iceberg_packed", "minecraft:iceberg_blue", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:blue_ice", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let DEEP_LUKEWARM_OCEAN* = Biome(
  name: "minecraft:deep_lukewarm_ocean",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:seagrass_deep_warm", "minecraft:kelp_warm", "minecraft:freeze_top_layer"],
)

let DEEP_OCEAN* = Biome(
  name: "minecraft:deep_ocean",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:seagrass_deep", "minecraft:kelp_cold", "minecraft:freeze_top_layer"],
)

let DESERT* = Biome(
  name: "minecraft:desert",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:fossil_upper", "minecraft:fossil_lower", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:desert_well", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:patch_dry_grass_desert", "minecraft:patch_dead_bush_2", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_sugar_cane_desert", "minecraft:patch_pumpkin", "minecraft:patch_cactus_desert", "minecraft:freeze_top_layer"],
)

let DRIPSTONE_CAVES* = Biome(
  name: "minecraft:dripstone_caves",
  hasPrecipitation: true,
  temperature: 0.8'f32,
  downfall: 0.4'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:large_dripstone", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper_large", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:dripstone_cluster", "minecraft:pointed_dripstone", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_tall_grass_2", "minecraft:trees_plains", "minecraft:flower_plains", "minecraft:patch_grass_plain", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:freeze_top_layer"],
)

let END_BARRENS* = Biome(
  name: "minecraft:end_barrens",
  hasPrecipitation: false,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @[],
  features: @[],
)

let END_HIGHLANDS* = Biome(
  name: "minecraft:end_highlands",
  hasPrecipitation: false,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @[],
  features: @["minecraft:end_gateway_return", "minecraft:chorus_plant"],
)

let END_MIDLANDS* = Biome(
  name: "minecraft:end_midlands",
  hasPrecipitation: false,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @[],
  features: @[],
)

let ERODED_BADLANDS* = Biome(
  name: "minecraft:eroded_badlands",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:ore_gold_extra", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_grass_badlands", "minecraft:patch_dry_grass_badlands", "minecraft:patch_dead_bush_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_sugar_cane_badlands", "minecraft:patch_pumpkin", "minecraft:patch_cactus_decorated", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let FLOWER_FOREST* = Biome(
  name: "minecraft:flower_forest",
  hasPrecipitation: true,
  temperature: 0.7'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:flower_forest_flowers", "minecraft:trees_flower_forest", "minecraft:flower_flower_forest", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let FOREST* = Biome(
  name: "minecraft:forest",
  hasPrecipitation: true,
  temperature: 0.7'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:forest_flowers", "minecraft:trees_birch_and_oak_leaf_litter", "minecraft:patch_bush", "minecraft:flower_default", "minecraft:patch_grass_forest", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let FROZEN_OCEAN* = Biome(
  name: "minecraft:frozen_ocean",
  hasPrecipitation: true,
  temperature: 0.0'f32,
  downfall: 0.5'f32,
  temperatureModifier: "frozen",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:iceberg_packed", "minecraft:iceberg_blue", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:blue_ice", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let FROZEN_PEAKS* = Biome(
  name: "minecraft:frozen_peaks",
  hasPrecipitation: true,
  temperature: -0.7'f32,
  downfall: 0.9'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:ore_emerald", "minecraft:ore_infested", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:spring_lava_frozen", "minecraft:glow_lichen", "minecraft:freeze_top_layer"],
)

let FROZEN_RIVER* = Biome(
  name: "minecraft:frozen_river",
  hasPrecipitation: true,
  temperature: 0.0'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:patch_bush", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let GROVE* = Biome(
  name: "minecraft:grove",
  hasPrecipitation: true,
  temperature: -0.2'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:ore_emerald", "minecraft:ore_infested", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:spring_lava_frozen", "minecraft:glow_lichen", "minecraft:trees_grove", "minecraft:patch_pumpkin", "minecraft:freeze_top_layer"],
)

let ICE_SPIKES* = Biome(
  name: "minecraft:ice_spikes",
  hasPrecipitation: true,
  temperature: 0.0'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ice_spike", "minecraft:ice_patch", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_snowy", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let JAGGED_PEAKS* = Biome(
  name: "minecraft:jagged_peaks",
  hasPrecipitation: true,
  temperature: -0.7'f32,
  downfall: 0.9'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:ore_emerald", "minecraft:ore_infested", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:spring_lava_frozen", "minecraft:glow_lichen", "minecraft:freeze_top_layer"],
)

let JUNGLE* = Biome(
  name: "minecraft:jungle",
  hasPrecipitation: true,
  temperature: 0.95'f32,
  downfall: 0.9'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:bamboo_light", "minecraft:trees_jungle", "minecraft:flower_warm", "minecraft:patch_grass_jungle", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:vines", "minecraft:patch_melon", "minecraft:freeze_top_layer"],
)

let LUKEWARM_OCEAN* = Biome(
  name: "minecraft:lukewarm_ocean",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:seagrass_warm", "minecraft:kelp_warm", "minecraft:freeze_top_layer"],
)

let LUSH_CAVES* = Biome(
  name: "minecraft:lush_caves",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:ore_clay", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_tall_grass_2", "minecraft:lush_caves_ceiling_vegetation", "minecraft:cave_vines", "minecraft:lush_caves_clay", "minecraft:lush_caves_vegetation", "minecraft:rooted_azalea_tree", "minecraft:spore_blossom", "minecraft:classic_vines_cave_feature", "minecraft:freeze_top_layer"],
)

let MANGROVE_SWAMP* = Biome(
  name: "minecraft:mangrove_swamp",
  hasPrecipitation: true,
  temperature: 0.8'f32,
  downfall: 0.9'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:fossil_upper", "minecraft:fossil_lower", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_grass", "minecraft:disk_clay", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_mangrove", "minecraft:patch_grass_normal", "minecraft:patch_dead_bush", "minecraft:patch_waterlily", "minecraft:seagrass_swamp", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let MEADOW* = Biome(
  name: "minecraft:meadow",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:ore_emerald", "minecraft:ore_infested", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_tall_grass_2", "minecraft:patch_grass_meadow", "minecraft:flower_meadow", "minecraft:trees_meadow", "minecraft:wildflowers_meadow", "minecraft:freeze_top_layer"],
)

let MUSHROOM_FIELDS* = Biome(
  name: "minecraft:mushroom_fields",
  hasPrecipitation: true,
  temperature: 0.9'f32,
  downfall: 1.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:mushroom_island_vegetation", "minecraft:brown_mushroom_taiga", "minecraft:red_mushroom_taiga", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let NETHER_WASTES* = Biome(
  name: "minecraft:nether_wastes",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:nether_cave"],
  features: @["minecraft:spring_open", "minecraft:patch_fire", "minecraft:patch_soul_fire", "minecraft:glowstone_extra", "minecraft:glowstone", "minecraft:brown_mushroom_nether", "minecraft:red_mushroom_nether", "minecraft:ore_magma", "minecraft:spring_closed", "minecraft:ore_gravel_nether", "minecraft:ore_blackstone", "minecraft:ore_gold_nether", "minecraft:ore_quartz_nether", "minecraft:ore_ancient_debris_large", "minecraft:ore_debris_small", "minecraft:spring_lava", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal"],
)

let OCEAN* = Biome(
  name: "minecraft:ocean",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:seagrass_normal", "minecraft:kelp_cold", "minecraft:freeze_top_layer"],
)

let OLD_GROWTH_BIRCH_FOREST* = Biome(
  name: "minecraft:old_growth_birch_forest",
  hasPrecipitation: true,
  temperature: 0.6'f32,
  downfall: 0.6'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:forest_flowers", "minecraft:wildflowers_birch_forest", "minecraft:birch_tall", "minecraft:patch_bush", "minecraft:flower_default", "minecraft:patch_grass_forest", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let OLD_GROWTH_PINE_TAIGA* = Biome(
  name: "minecraft:old_growth_pine_taiga",
  hasPrecipitation: true,
  temperature: 0.3'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:forest_rock", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_large_fern", "minecraft:trees_old_growth_pine_taiga", "minecraft:flower_default", "minecraft:patch_grass_taiga", "minecraft:patch_dead_bush", "minecraft:brown_mushroom_old_growth", "minecraft:red_mushroom_old_growth", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:patch_berry_common", "minecraft:freeze_top_layer"],
)

let OLD_GROWTH_SPRUCE_TAIGA* = Biome(
  name: "minecraft:old_growth_spruce_taiga",
  hasPrecipitation: true,
  temperature: 0.25'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:forest_rock", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_large_fern", "minecraft:trees_old_growth_spruce_taiga", "minecraft:flower_default", "minecraft:patch_grass_taiga", "minecraft:patch_dead_bush", "minecraft:brown_mushroom_old_growth", "minecraft:red_mushroom_old_growth", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:patch_berry_common", "minecraft:freeze_top_layer"],
)

let PALE_GARDEN* = Biome(
  name: "minecraft:pale_garden",
  hasPrecipitation: true,
  temperature: 0.7'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:pale_garden_vegetation", "minecraft:pale_moss_patch", "minecraft:pale_garden_flowers", "minecraft:flower_pale_garden", "minecraft:patch_grass_forest", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let PLAINS* = Biome(
  name: "minecraft:plains",
  hasPrecipitation: true,
  temperature: 0.8'f32,
  downfall: 0.4'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_tall_grass_2", "minecraft:patch_bush", "minecraft:trees_plains", "minecraft:flower_plains", "minecraft:patch_grass_plain", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let RIVER* = Biome(
  name: "minecraft:river",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:patch_bush", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:seagrass_river", "minecraft:freeze_top_layer"],
)

let SAVANNA* = Biome(
  name: "minecraft:savanna",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_tall_grass", "minecraft:trees_savanna", "minecraft:flower_warm", "minecraft:patch_grass_savanna", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let SAVANNA_PLATEAU* = Biome(
  name: "minecraft:savanna_plateau",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_tall_grass", "minecraft:trees_savanna", "minecraft:flower_warm", "minecraft:patch_grass_savanna", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let SMALL_END_ISLANDS* = Biome(
  name: "minecraft:small_end_islands",
  hasPrecipitation: false,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @[],
  features: @["minecraft:end_island_decorated"],
)

let SNOWY_BEACH* = Biome(
  name: "minecraft:snowy_beach",
  hasPrecipitation: true,
  temperature: 0.05'f32,
  downfall: 0.3'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let SNOWY_PLAINS* = Biome(
  name: "minecraft:snowy_plains",
  hasPrecipitation: true,
  temperature: 0.0'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_snowy", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let SNOWY_SLOPES* = Biome(
  name: "minecraft:snowy_slopes",
  hasPrecipitation: true,
  temperature: -0.3'f32,
  downfall: 0.9'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:ore_emerald", "minecraft:ore_infested", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:spring_lava_frozen", "minecraft:glow_lichen", "minecraft:patch_pumpkin", "minecraft:freeze_top_layer"],
)

let SNOWY_TAIGA* = Biome(
  name: "minecraft:snowy_taiga",
  hasPrecipitation: true,
  temperature: -0.5'f32,
  downfall: 0.4'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_large_fern", "minecraft:trees_taiga", "minecraft:flower_default", "minecraft:patch_grass_taiga_2", "minecraft:brown_mushroom_taiga", "minecraft:red_mushroom_taiga", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:patch_berry_rare", "minecraft:freeze_top_layer"],
)

let SOUL_SAND_VALLEY* = Biome(
  name: "minecraft:soul_sand_valley",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:nether_cave"],
  features: @["minecraft:basalt_pillar", "minecraft:spring_open", "minecraft:patch_fire", "minecraft:patch_soul_fire", "minecraft:glowstone_extra", "minecraft:glowstone", "minecraft:patch_crimson_roots", "minecraft:ore_magma", "minecraft:spring_closed", "minecraft:ore_soul_sand", "minecraft:ore_gravel_nether", "minecraft:ore_blackstone", "minecraft:ore_gold_nether", "minecraft:ore_quartz_nether", "minecraft:ore_ancient_debris_large", "minecraft:ore_debris_small", "minecraft:spring_lava"],
)

let SPARSE_JUNGLE* = Biome(
  name: "minecraft:sparse_jungle",
  hasPrecipitation: true,
  temperature: 0.95'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_sparse_jungle", "minecraft:flower_warm", "minecraft:patch_grass_jungle", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:vines", "minecraft:patch_melon_sparse", "minecraft:freeze_top_layer"],
)

let STONY_PEAKS* = Biome(
  name: "minecraft:stony_peaks",
  hasPrecipitation: true,
  temperature: 1.0'f32,
  downfall: 0.3'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:ore_emerald", "minecraft:ore_infested", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:freeze_top_layer"],
)

let STONY_SHORE* = Biome(
  name: "minecraft:stony_shore",
  hasPrecipitation: true,
  temperature: 0.2'f32,
  downfall: 0.3'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let SULFUR_CAVES* = Biome(
  name: "minecraft:sulfur_caves",
  hasPrecipitation: true,
  temperature: 0.8'f32,
  downfall: 0.4'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:rooted_sulfur_spring", "minecraft:sulfur_pool", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:sulfur_spike_cluster", "minecraft:sulfur_spike", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_tall_grass_2", "minecraft:freeze_top_layer"],
)

let SUNFLOWER_PLAINS* = Biome(
  name: "minecraft:sunflower_plains",
  hasPrecipitation: true,
  temperature: 0.8'f32,
  downfall: 0.4'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_tall_grass_2", "minecraft:patch_sunflower", "minecraft:trees_plains", "minecraft:flower_plains", "minecraft:patch_grass_plain", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let SWAMP* = Biome(
  name: "minecraft:swamp",
  hasPrecipitation: true,
  temperature: 0.8'f32,
  downfall: 0.9'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:fossil_upper", "minecraft:fossil_lower", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_clay", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_swamp", "minecraft:flower_swamp", "minecraft:patch_grass_normal", "minecraft:patch_dead_bush", "minecraft:patch_waterlily", "minecraft:brown_mushroom_swamp", "minecraft:red_mushroom_swamp", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_sugar_cane_swamp", "minecraft:patch_pumpkin", "minecraft:patch_firefly_bush_swamp", "minecraft:patch_firefly_bush_near_water_swamp", "minecraft:seagrass_swamp", "minecraft:freeze_top_layer"],
)

let TAIGA* = Biome(
  name: "minecraft:taiga",
  hasPrecipitation: true,
  temperature: 0.25'f32,
  downfall: 0.8'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:patch_large_fern", "minecraft:trees_taiga", "minecraft:flower_default", "minecraft:patch_grass_taiga_2", "minecraft:brown_mushroom_taiga", "minecraft:red_mushroom_taiga", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:patch_berry_common", "minecraft:freeze_top_layer"],
)

let THE_END* = Biome(
  name: "minecraft:the_end",
  hasPrecipitation: false,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @[],
  features: @["minecraft:end_spike", "minecraft:end_platform"],
)

let THE_VOID* = Biome(
  name: "minecraft:the_void",
  hasPrecipitation: false,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @[],
  features: @["minecraft:void_start_platform"],
)

let WARM_OCEAN* = Biome(
  name: "minecraft:warm_ocean",
  hasPrecipitation: true,
  temperature: 0.5'f32,
  downfall: 0.5'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_water", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:warm_ocean_vegetation", "minecraft:seagrass_warm", "minecraft:sea_pickle", "minecraft:freeze_top_layer"],
)

let WARPED_FOREST* = Biome(
  name: "minecraft:warped_forest",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:nether_cave"],
  features: @["minecraft:spring_open", "minecraft:patch_fire", "minecraft:patch_soul_fire", "minecraft:glowstone_extra", "minecraft:glowstone", "minecraft:ore_magma", "minecraft:spring_closed", "minecraft:ore_gravel_nether", "minecraft:ore_blackstone", "minecraft:ore_gold_nether", "minecraft:ore_quartz_nether", "minecraft:ore_ancient_debris_large", "minecraft:ore_debris_small", "minecraft:spring_lava", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:warped_fungi", "minecraft:warped_forest_vegetation", "minecraft:nether_sprouts", "minecraft:twisting_vines"],
)

let WINDSWEPT_FOREST* = Biome(
  name: "minecraft:windswept_forest",
  hasPrecipitation: true,
  temperature: 0.2'f32,
  downfall: 0.3'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:ore_emerald", "minecraft:ore_infested", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_windswept_forest", "minecraft:patch_bush", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let WINDSWEPT_GRAVELLY_HILLS* = Biome(
  name: "minecraft:windswept_gravelly_hills",
  hasPrecipitation: true,
  temperature: 0.2'f32,
  downfall: 0.3'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:ore_emerald", "minecraft:ore_infested", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_windswept_hills", "minecraft:patch_bush", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let WINDSWEPT_HILLS* = Biome(
  name: "minecraft:windswept_hills",
  hasPrecipitation: true,
  temperature: 0.2'f32,
  downfall: 0.3'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:ore_emerald", "minecraft:ore_infested", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_windswept_hills", "minecraft:patch_bush", "minecraft:flower_default", "minecraft:patch_grass_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let WINDSWEPT_SAVANNA* = Biome(
  name: "minecraft:windswept_savanna",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_windswept_savanna", "minecraft:flower_default", "minecraft:patch_grass_normal", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_pumpkin", "minecraft:patch_sugar_cane", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

let WOODED_BADLANDS* = Biome(
  name: "minecraft:wooded_badlands",
  hasPrecipitation: false,
  temperature: 2.0'f32,
  downfall: 0.0'f32,
  temperatureModifier: "",
  carvers: @["minecraft:cave", "minecraft:cave_extra_underground", "minecraft:canyon"],
  features: @["minecraft:lake_lava_underground", "minecraft:lake_lava_surface", "minecraft:amethyst_geode", "minecraft:monster_room", "minecraft:monster_room_deep", "minecraft:ore_dirt", "minecraft:ore_gravel", "minecraft:ore_granite_upper", "minecraft:ore_granite_lower", "minecraft:ore_diorite_upper", "minecraft:ore_diorite_lower", "minecraft:ore_andesite_upper", "minecraft:ore_andesite_lower", "minecraft:ore_tuff", "minecraft:ore_coal_upper", "minecraft:ore_coal_lower", "minecraft:ore_iron_upper", "minecraft:ore_iron_middle", "minecraft:ore_iron_small", "minecraft:ore_gold", "minecraft:ore_gold_lower", "minecraft:ore_redstone", "minecraft:ore_redstone_lower", "minecraft:ore_diamond", "minecraft:ore_diamond_medium", "minecraft:ore_diamond_large", "minecraft:ore_diamond_buried", "minecraft:ore_lapis", "minecraft:ore_lapis_buried", "minecraft:ore_copper", "minecraft:underwater_magma", "minecraft:ore_gold_extra", "minecraft:disk_sand", "minecraft:disk_clay", "minecraft:disk_gravel", "minecraft:spring_water", "minecraft:spring_lava", "minecraft:glow_lichen", "minecraft:trees_badlands", "minecraft:patch_grass_badlands", "minecraft:patch_dry_grass_badlands", "minecraft:patch_dead_bush_badlands", "minecraft:brown_mushroom_normal", "minecraft:red_mushroom_normal", "minecraft:patch_sugar_cane_badlands", "minecraft:patch_pumpkin", "minecraft:patch_cactus_decorated", "minecraft:patch_firefly_bush_near_water", "minecraft:freeze_top_layer"],
)

proc allBiomes*(): seq[Biome] =
  @[
    BADLANDS,
    BAMBOO_JUNGLE,
    BASALT_DELTAS,
    BEACH,
    BIRCH_FOREST,
    CHERRY_GROVE,
    COLD_OCEAN,
    CRIMSON_FOREST,
    DAPPLED_FOREST,
    DARK_FOREST,
    DEEP_COLD_OCEAN,
    DEEP_DARK,
    DEEP_FROZEN_OCEAN,
    DEEP_LUKEWARM_OCEAN,
    DEEP_OCEAN,
    DESERT,
    DRIPSTONE_CAVES,
    END_BARRENS,
    END_HIGHLANDS,
    END_MIDLANDS,
    ERODED_BADLANDS,
    FLOWER_FOREST,
    FOREST,
    FROZEN_OCEAN,
    FROZEN_PEAKS,
    FROZEN_RIVER,
    GROVE,
    ICE_SPIKES,
    JAGGED_PEAKS,
    JUNGLE,
    LUKEWARM_OCEAN,
    LUSH_CAVES,
    MANGROVE_SWAMP,
    MEADOW,
    MUSHROOM_FIELDS,
    NETHER_WASTES,
    OCEAN,
    OLD_GROWTH_BIRCH_FOREST,
    OLD_GROWTH_PINE_TAIGA,
    OLD_GROWTH_SPRUCE_TAIGA,
    PALE_GARDEN,
    PLAINS,
    RIVER,
    SAVANNA,
    SAVANNA_PLATEAU,
    SMALL_END_ISLANDS,
    SNOWY_BEACH,
    SNOWY_PLAINS,
    SNOWY_SLOPES,
    SNOWY_TAIGA,
    SOUL_SAND_VALLEY,
    SPARSE_JUNGLE,
    STONY_PEAKS,
    STONY_SHORE,
    SULFUR_CAVES,
    SUNFLOWER_PLAINS,
    SWAMP,
    TAIGA,
    THE_END,
    THE_VOID,
    WARM_OCEAN,
    WARPED_FOREST,
    WINDSWEPT_FOREST,
    WINDSWEPT_GRAVELLY_HILLS,
    WINDSWEPT_HILLS,
    WINDSWEPT_SAVANNA,
    WOODED_BADLANDS,
  ]

proc biomeFromName*(name: string): (bool, Biome) =
  case name
  of "minecraft:badlands", "badlands":
    (true, BADLANDS)
  of "minecraft:bamboo_jungle", "bamboo_jungle":
    (true, BAMBOO_JUNGLE)
  of "minecraft:basalt_deltas", "basalt_deltas":
    (true, BASALT_DELTAS)
  of "minecraft:beach", "beach":
    (true, BEACH)
  of "minecraft:birch_forest", "birch_forest":
    (true, BIRCH_FOREST)
  of "minecraft:cherry_grove", "cherry_grove":
    (true, CHERRY_GROVE)
  of "minecraft:cold_ocean", "cold_ocean":
    (true, COLD_OCEAN)
  of "minecraft:crimson_forest", "crimson_forest":
    (true, CRIMSON_FOREST)
  of "minecraft:dappled_forest", "dappled_forest":
    (true, DAPPLED_FOREST)
  of "minecraft:dark_forest", "dark_forest":
    (true, DARK_FOREST)
  of "minecraft:deep_cold_ocean", "deep_cold_ocean":
    (true, DEEP_COLD_OCEAN)
  of "minecraft:deep_dark", "deep_dark":
    (true, DEEP_DARK)
  of "minecraft:deep_frozen_ocean", "deep_frozen_ocean":
    (true, DEEP_FROZEN_OCEAN)
  of "minecraft:deep_lukewarm_ocean", "deep_lukewarm_ocean":
    (true, DEEP_LUKEWARM_OCEAN)
  of "minecraft:deep_ocean", "deep_ocean":
    (true, DEEP_OCEAN)
  of "minecraft:desert", "desert":
    (true, DESERT)
  of "minecraft:dripstone_caves", "dripstone_caves":
    (true, DRIPSTONE_CAVES)
  of "minecraft:end_barrens", "end_barrens":
    (true, END_BARRENS)
  of "minecraft:end_highlands", "end_highlands":
    (true, END_HIGHLANDS)
  of "minecraft:end_midlands", "end_midlands":
    (true, END_MIDLANDS)
  of "minecraft:eroded_badlands", "eroded_badlands":
    (true, ERODED_BADLANDS)
  of "minecraft:flower_forest", "flower_forest":
    (true, FLOWER_FOREST)
  of "minecraft:forest", "forest":
    (true, FOREST)
  of "minecraft:frozen_ocean", "frozen_ocean":
    (true, FROZEN_OCEAN)
  of "minecraft:frozen_peaks", "frozen_peaks":
    (true, FROZEN_PEAKS)
  of "minecraft:frozen_river", "frozen_river":
    (true, FROZEN_RIVER)
  of "minecraft:grove", "grove":
    (true, GROVE)
  of "minecraft:ice_spikes", "ice_spikes":
    (true, ICE_SPIKES)
  of "minecraft:jagged_peaks", "jagged_peaks":
    (true, JAGGED_PEAKS)
  of "minecraft:jungle", "jungle":
    (true, JUNGLE)
  of "minecraft:lukewarm_ocean", "lukewarm_ocean":
    (true, LUKEWARM_OCEAN)
  of "minecraft:lush_caves", "lush_caves":
    (true, LUSH_CAVES)
  of "minecraft:mangrove_swamp", "mangrove_swamp":
    (true, MANGROVE_SWAMP)
  of "minecraft:meadow", "meadow":
    (true, MEADOW)
  of "minecraft:mushroom_fields", "mushroom_fields":
    (true, MUSHROOM_FIELDS)
  of "minecraft:nether_wastes", "nether_wastes":
    (true, NETHER_WASTES)
  of "minecraft:ocean", "ocean":
    (true, OCEAN)
  of "minecraft:old_growth_birch_forest", "old_growth_birch_forest":
    (true, OLD_GROWTH_BIRCH_FOREST)
  of "minecraft:old_growth_pine_taiga", "old_growth_pine_taiga":
    (true, OLD_GROWTH_PINE_TAIGA)
  of "minecraft:old_growth_spruce_taiga", "old_growth_spruce_taiga":
    (true, OLD_GROWTH_SPRUCE_TAIGA)
  of "minecraft:pale_garden", "pale_garden":
    (true, PALE_GARDEN)
  of "minecraft:plains", "plains":
    (true, PLAINS)
  of "minecraft:river", "river":
    (true, RIVER)
  of "minecraft:savanna", "savanna":
    (true, SAVANNA)
  of "minecraft:savanna_plateau", "savanna_plateau":
    (true, SAVANNA_PLATEAU)
  of "minecraft:small_end_islands", "small_end_islands":
    (true, SMALL_END_ISLANDS)
  of "minecraft:snowy_beach", "snowy_beach":
    (true, SNOWY_BEACH)
  of "minecraft:snowy_plains", "snowy_plains":
    (true, SNOWY_PLAINS)
  of "minecraft:snowy_slopes", "snowy_slopes":
    (true, SNOWY_SLOPES)
  of "minecraft:snowy_taiga", "snowy_taiga":
    (true, SNOWY_TAIGA)
  of "minecraft:soul_sand_valley", "soul_sand_valley":
    (true, SOUL_SAND_VALLEY)
  of "minecraft:sparse_jungle", "sparse_jungle":
    (true, SPARSE_JUNGLE)
  of "minecraft:stony_peaks", "stony_peaks":
    (true, STONY_PEAKS)
  of "minecraft:stony_shore", "stony_shore":
    (true, STONY_SHORE)
  of "minecraft:sulfur_caves", "sulfur_caves":
    (true, SULFUR_CAVES)
  of "minecraft:sunflower_plains", "sunflower_plains":
    (true, SUNFLOWER_PLAINS)
  of "minecraft:swamp", "swamp":
    (true, SWAMP)
  of "minecraft:taiga", "taiga":
    (true, TAIGA)
  of "minecraft:the_end", "the_end":
    (true, THE_END)
  of "minecraft:the_void", "the_void":
    (true, THE_VOID)
  of "minecraft:warm_ocean", "warm_ocean":
    (true, WARM_OCEAN)
  of "minecraft:warped_forest", "warped_forest":
    (true, WARPED_FOREST)
  of "minecraft:windswept_forest", "windswept_forest":
    (true, WINDSWEPT_FOREST)
  of "minecraft:windswept_gravelly_hills", "windswept_gravelly_hills":
    (true, WINDSWEPT_GRAVELLY_HILLS)
  of "minecraft:windswept_hills", "windswept_hills":
    (true, WINDSWEPT_HILLS)
  of "minecraft:windswept_savanna", "windswept_savanna":
    (true, WINDSWEPT_SAVANNA)
  of "minecraft:wooded_badlands", "wooded_badlands":
    (true, WOODED_BADLANDS)
  else:
    (false, Biome())
