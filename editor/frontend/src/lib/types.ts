// 与 Go 端 editor/internal/project、gamedata 的 JSON 一一对应

export interface Manifest {
  id: string
  name: string
  version: string
  author: string
  game: string
  description: string
}

export interface NPC {
  local: number
  map: number
  name: string
  act: number
  model: number // 自定义模型 @model:N, 0 = 用原版 act
  pose: number
  pos: [number, number, number]
  facing: number
  talk: boolean
  event: number
}

export type BlockType = "say" | "notice" | "money" | "item" | "shop" | "quest" | "flag" | "if_flag" | "if_quest" | "if_item" | "battle" | "var" | "if_var" | "party" | "end"

/** 物品引用: 原版物品填 item, 本 mod 物品填 modItem (二选一) */
export interface ItemRef {
  item?: number
  modItem?: number
}

export interface Block {
  type: BlockType
  speaker?: string // "npc:N" | "player" | "actor:N"
  text?: string
  amount?: number
  item?: number
  modItem?: number // 本 mod 的物品 (@item:N), 和 item 二选一
  itemName?: string
  goods?: ItemRef[] // 商店卖的东西
  count?: number
  quiet?: boolean // 金钱 / 道具: 不弹「得到【…】」提示
  flag?: number
  on?: boolean
  quest?: number
  step?: "accept" | "done" // 任务积木
  state?: "none" | "active" | "done" // 如果任务
  battle?: number // 开战: 本 mod 的战斗 (@battle:N)
  member?: number // 入队 / 离队: 2 嬴诗 / 3 桓远之
  var?: number // 变量 / 如果变量
  op?: "set" | "add"
  cmp?: "ge" | "eq"
  value?: number
  then?: Block[]
  else?: Block[]
}

export interface GameEvent {
  local: number
  name: string
  blocks: Block[]
}

export interface Flag {
  local: number
  name: string
}

export interface Anim {
  name: string
  seconds: number
}

export interface CustomModel {
  local: number
  name: string
  file: string
  scale: number
  yaw: number
  idle: string
  walk: string
  anims: Anim[]
  triangles: number
  size: number
  ground?: number // 脚底高度 (模型单位), 显示时抬高 -ground
}

export interface Project {
  dir: string
  manifest: Manifest
  npcs: NPC[]
  events: GameEvent[]
  flags: Flag[]
  models: CustomModel[]
  items: ModItem[]
  quests: Quest[]
  monsters: ModMonster[]
  battles: ModBattle[]
  vars: ModVar[]
  encounters: Encounter[]
  overrides: Override[]
  npcEdits: NpcEdit[]
  characters: CharEdit[]
  newGame: NewGameEdit | null
  skills: ModSkill[]
  skillEdits: SkillEdit[]
}

/** 本 mod 的变量 (计数器 0–65535, 跟存档保存) */
export interface ModVar {
  local: number
  name: string
}

/** 把本 mod 的战斗加进某张地图原版遇敌区域 (重复 = 权重); zones 空 = 全部区域 */
export interface Encounter {
  map: number
  battle: number
  weight: number
  zones: number[]
}

/** 本 mod 的怪物: 复制原版怪物 base (模型、普攻、技能、AI、抗性照抄), 只改名字 / 说明 / 数值 / 经验 / 金钱 / 战后掉落 */
export interface ModMonster extends MonsterStats {
  local: number
  base: number
  name: string
  desc: string
  exp: number
  money: number
  dropRate: number
  dropItem?: number
  dropModItem?: number
  counter?: number // 被打倒时这个变量 +1
  model?: number // 战斗模型: 本 mod 的自定义模型 (@model:N), 不填 = 原版模型
  poses?: Record<string, string> // 原版动作号 → 动画名
}

export interface MonsterStats {
  level: number
  hp: number
  mp: number
  sp: number
  atk: number
  def: number
  spd: number
  matk: number
  mdef: number
  hit: number
  eva: number
  mhit: number
  meva: number
}

/** 本 mod 的战斗: 复制原版普通战场 base (场景、镜头、战斗脚本), 每个敌人占原版的一个站位 at */
export interface ModBattle {
  local: number
  name: string
  base: number
  enemies: { at: number; monster?: number; modMonster?: number }[]
}

/** 原版怪物 (分类 110–120、在战场里出现过) */
export interface GameMonster extends MonsterStats {
  id: number
  name: string
  race: string
  desc: string
  exp: number
  money: number
  drop: [number, number]
  boss: boolean
  glb: string
  scale: number // 待机动作的 ACT 缩放 (预览用)
  poses: MonsterPose[] | null
}

/** 怪物在战斗里会播的一个动作 (帧数 / 命中记号照抄原版) */
export interface MonsterPose {
  q: number
  ticks: number
  loop: boolean
  hits: number
  uses: string[]
}

/** 原版普通战场 (战斗脚本只有音乐 / 先手 / 开场演出 / 回合) */
export interface GameBattlefield {
  id: number
  name: string
  scene: string
  initiative: number
  slots: { monster: number; name: string; pos: [number, number, number]; facing: number }[]
}

/** 任务 (记载「事」页): 文字 = ★/☆ + 任务名; 接受 / 完成旗标由编辑器自动分配 (@flag:900+N / 950+N) */
export interface Quest {
  local: number
  title: string
  main: boolean
}

/** 本 mod 的物品: 复制原版物品 base, 只改名字 / 说明 / 价格 / 恢复量 (编码同游戏 Formula.amount) */
export interface ModItem {
  local: number
  base: number
  name: string
  desc: string
  price: number
  fx1?: number[] // 恢复类才有: [0] 生命 [1] 体力
  fx2?: number[] // [0] 灵力
}

/** 原版物品 (battle.json objs 分类 201–211) */
export interface GameItem {
  id: number
  name: string
  sub: number
  cat: string
  price: number
  desc: string
  icon: string
  fx1: number[] | null
  fx2: number[] | null
}

export interface Issue {
  level: "error" | "warning"
  where: string
  message: string
}

export interface MapInfo {
  id: number
  name: string
  title: string
  kind: string
}

export interface OrigNpc {
  actor: number
  name: string
  act: number
  pos: [number, number, number]
  facing: number
  event: number
}

export interface MapDetail extends MapInfo {
  scene: string
  offset: [number, number, number]
  npcs: OrigNpc[] | null
  boxes: { event: number; min: [number, number, number]; max: [number, number, number] }[] | null
  zones: EncounterZone[] | null
}

/** 原版遇敌区域 (x / z 范围), 战场列表里重复 = 权重 */
export interface EncounterZone {
  min: [number, number]
  max: [number, number]
  battles: number[]
  names: string[]
}

export interface Model {
  act: number
  label: string
  glb: string
}

export interface Status {
  gameRoot: string
  dataOk: boolean
  error: string
  godot: string
  godotOk: boolean
  authorKey: boolean
}

export type Selection =
  | { kind: "manifest" }
  | { kind: "npc"; local: number }
  | { kind: "event"; local: number }
  | { kind: "flag"; local: number }
  | { kind: "model"; local: number }
  | { kind: "item"; local: number }
  | { kind: "quest"; local: number }
  | { kind: "monster"; local: number }
  | { kind: "battle"; local: number }
  | { kind: "var"; local: number }
  | { kind: "encounters"; map: number }
  | { kind: "override"; id: number }
  | { kind: "orig_npc"; map: number; actor: number }
  | { kind: "member"; id: number }
  | { kind: "newgame" }
  | { kind: "skill"; local: number }
  | { kind: "skill_edit"; id: number }
  | null

/** 原版剧情线路 (只读) */
export interface StoryEvent {
  id: number
  map: string
  mid: number
  trig: string
  talk: number // 对白句数
  acc: string[] | null // 接受的任务
  comp: string[] | null // 完成的任务
  name: string
  first: string
  reached: boolean // 自动通关触发过 (有剧情快照)
  kind: "story" | "side" | "talk" | "other" // 推进剧情 (旗标被剧情事件判断, 见 storyEvents) / 支线任务 (☆) / 路人对话 / 触发点·旁白·出入口
  time: number // 当时的游玩秒数
}

export interface Chapter {
  key: string
  group: string
  title: string
  sub: string
  events: StoryEvent[]
  tasks: Task[] | null // 有剧情快照时: 章节 → 任务 → 剧情
  side: Task[] | null // 这一章的支线任务
}

/** 原版事件 = 指令 [位置, 指令, 参数...] + 概要 */
export interface EventInfo {
  id: number
  file: string
  code: (string | number | number[])[][] | null
  shared: number[] | null
  triggers: string[] | null
  lines: string[] | null
  battles: string[] | null
  maps: number[] | null
}

/** 事件指令 (操作数类型: w u16, s i16, d i32, r 跳转, a 角色, m 地图, f 旗标, i 物品, b 战场, n 名字号, e 事件, M 曲目, c u8, T 文本, F 列表, R 跳转表) */
export interface Opcode {
  code: string
  name: string
  operands: string
  status: string
  note: string
  count: number
}

export interface Names {
  people: Record<string, string>
  items: Record<string, string>
  battles: Record<string, string>
}

/** 方案改过的原版事件: 整段指令 [位置, 指令, 参数...] (位置只是标签, 跳转写目标位置) */
export interface Override {
  id: number
  name: string
  code: Instr[]
}
export type Instr = (string | number | (string | number)[])[]

/** 改 / 删原版地图上的 NPC (只写改了的项) */
export interface NpcEdit {
  map: number
  actor: number
  remove?: boolean
  pos?: [number, number, number]
  act?: number
  model?: number
  facing?: number
  event?: number
  modEvent?: number
  name?: string
}

/** 剧情快照: 事件开始前那一刻在场的角色 (自动通关录的) */
export interface CastMember {
  actor: number
  name: string
  act: number
  pose: number
  pos: [number, number, number]
  facing: number
  event: number
  player: boolean
  glb: string
  scale: number
}

export interface Snapshot {
  event: number
  borrowed: number // 借用的是哪个事件的快照 (0 = 自己的)
  map: number
  playSeconds: number
  cast: CastMember[] | null
  cam: { ang: [number, number, number]; d: number; k: number } | null // 当时的游戏镜头
}

/** 章节下的一个任务 (原版任务簿 ★主线 / ☆支线) 和这一步里发生的剧情 */
export interface Task {
  title: string // 空 = 没有进行中的主线任务
  main: boolean
  done: boolean
  events: StoryEvent[]
}

// ---------------- 队员 / 开局 / 技能 (E4 / E5) ----------------

export interface SkillRef { skill?: number; modSkill?: number }

/** 成长表一行: 升到 lv 级时加的 12 项 (HP MP SP 攻 防 仙攻 仙防 命中 回避 仙命中 仙回避 速度) + 这一级学会的技能 */
export interface GrowthRow { lv: number; inc: number[]; learn: SkillRef }

export interface CharEdit {
  id: number // 1 车芸 / 2 嬴诗 / 3 桓远之
  name?: string
  desc?: string
  stats?: Record<string, number>
  growth?: GrowthRow[]
  mapAct?: number
  mapModel?: number
}

export interface NewGameEdit {
  money?: number
  items?: ItemRef[]
  party?: number[]
  skills?: Record<string, SkillRef[]>
  equip?: Record<string, number[]>
}

export interface ModSkill {
  local: number
  base: number
  name: string
  desc: string
  power: number
  cost: Record<string, number>
  fx1?: number[]
  fx2?: number[]
}

export interface SkillEdit { id: number; name?: string; desc?: string; power?: number; cost?: Record<string, number> }

/** 原版队员 */
export interface GameMember {
  id: number
  name: string
  desc: string
  stats: Record<string, number>
  growth: number[][] // [等级, 12 项, 习得法术]
  act: number
}

export interface GameNewGame { money: number; items: number[]; equip: Record<string, number[]>; skills: Record<string, number[]> }

/** 原版技能 */
export interface GameSkill {
  id: number
  name: string
  desc: string
  sub: number
  cat: string
  note: string
  power: number
  cost: Record<string, number> | null
  fx1: number[] | null
  fx2: number[] | null
  owner: number // 原版谁会 (0 = 敌人 / 没人)
  copy: boolean // 能复制成新技能
}
