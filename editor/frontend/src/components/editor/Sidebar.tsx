import { Button } from "@/components/ui/button"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Skeleton } from "@/components/ui/skeleton"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { BoxIcon, FlagIcon, ListIcon, MapIcon, PackageOpenIcon, PawPrintIcon, PlusIcon, ScrollTextIcon, SwordsIcon, UserIcon, HashIcon, FootprintsIcon, PencilIcon, UsersIcon, SwordIcon, SparklesIcon } from "lucide-react"
import { ItemIcon, useGameItems } from "./ItemPicker"
import { useOpsAndNames } from "./EventViewer"
import { useGameSkills } from "./SkillForm"
import { Spinner } from "@/components/ui/spinner"
import { cn } from "@/lib/utils"
import type { MapInfo, Project, Selection } from "@/lib/types"

type Props = {
  project: Project
  maps: MapInfo[] | null
  mapId: number | null
  selection: Selection
  onMap: (id: number) => void
  onSelect: (s: Selection) => void
  onAddEvent: () => void
  onAddFlag: () => void
  onAddItem: () => void
  onAddQuest: () => void
  onAddMonster: () => void
  onAddBattle: () => void
  onAddVar: () => void
  onAddSkill: () => void
  onImportModel: () => void
  importing: boolean
}

function Heading({ children, action }: { children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <div className="mt-4 mb-1 flex items-center justify-between px-2 text-xs tracking-wide text-muted-foreground first:mt-1">
      {children}
      {action}
    </div>
  )
}

function Row({ active, icon, children, onClick, hint }: { active: boolean; icon: React.ReactNode; children: React.ReactNode; onClick: () => void; hint?: string }) {
  return (
    <button onClick={onClick}
      className={cn("flex h-8 w-full items-center gap-2 rounded-md px-2 text-left text-sm text-sidebar-foreground/90 hover:bg-sidebar-accent/60",
        active && "bg-sidebar-accent text-sidebar-accent-foreground ring-1 ring-primary/40")}>
      <span className="text-primary/80 [&_svg]:size-4">{icon}</span>
      <span className="min-w-0 flex-1 truncate">{children}</span>
      {hint && <span className="text-xs text-muted-foreground">{hint}</span>}
    </button>
  )
}

function AddButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button variant="ghost" size="icon-xs" onClick={onClick} aria-label={label}><PlusIcon /></Button>
      </TooltipTrigger>
      <TooltipContent>{label}</TooltipContent>
    </Tooltip>
  )
}

const KINDS = ["城镇", "户外", "室内", "迷宫", "地图", "剧情"]

export function Sidebar({ project: p, maps, mapId, selection, onMap, onSelect, onAddEvent, onAddFlag, onAddItem, onAddQuest, onAddMonster, onAddBattle, onAddVar, onAddSkill, onImportModel, importing }: Props) {
  const game = useGameItems()
  const [, names] = useOpsAndNames()
  const gskills = useGameSkills()
  const sel = (k: string, l?: number) => selection?.kind === k && (l === undefined || ("local" in selection && selection.local === l))
  const onMapNpcs = p.npcs.filter((n) => n.map === mapId)
  const otherMaps = [...new Set(p.npcs.filter((n) => n.map !== mapId).map((n) => n.map))]
  return (
    <ScrollArea className="h-full bg-sidebar">
      <div className="p-2">
        <Heading>项目</Heading>
        <Row active={sel("manifest")} icon={<PackageOpenIcon />} onClick={() => onSelect({ kind: "manifest" })}>mod 信息</Row>

        <Heading>地图</Heading>
        {maps === null ? (
          <Skeleton className="mx-2 h-8" />
        ) : (
          <Select value={mapId ? String(mapId) : undefined} onValueChange={(v) => onMap(Number(v))}>
            <SelectTrigger className="mx-auto w-[calc(100%-1rem)]"><MapIcon /><SelectValue placeholder="选择要编辑的地图" /></SelectTrigger>
            <SelectContent className="max-h-80">
              {KINDS.map((k) => (
                <SelectGroup key={k}>
                  <SelectLabel>{k}</SelectLabel>
                  {maps.filter((m) => m.kind === k).map((m) => (
                    <SelectItem key={m.id} value={String(m.id)}>{m.title || m.name} · {m.id}</SelectItem>
                  ))}
                </SelectGroup>
              ))}
            </SelectContent>
          </Select>
        )}
        <div className="mt-1 space-y-0.5 pl-2">
          {onMapNpcs.map((n) => (
            <Row key={n.local} active={sel("npc", n.local)} icon={<UserIcon />} onClick={() => onSelect({ kind: "npc", local: n.local })}>
              {n.name || `NPC ${n.local}`}
            </Row>
          ))}
          {mapId !== null && (
            <Row active={selection?.kind === "encounters"} icon={<FootprintsIcon />} onClick={() => onSelect({ kind: "encounters", map: mapId })}
              hint={`${p.encounters.filter((e) => e.map === mapId).length} 场 mod 战斗`}>遇敌</Row>
          )}
          {mapId !== null && onMapNpcs.length === 0 && (
            <p className="px-2 py-1 text-xs text-muted-foreground">这张图还没有 NPC。用地图上方的「放置 NPC」点地面添加。</p>
          )}
          {otherMaps.map((m) => (
            <Row key={m} active={false} icon={<MapIcon />} onClick={() => onMap(m)} hint={`${p.npcs.filter((n) => n.map === m).length} 个 NPC`}>
              {maps?.find((x) => x.id === m)?.title ?? m}
            </Row>
          ))}
        </div>

        <Heading>队员与开局</Heading>
        {[1, 2, 3].map((m) => (
          <Row key={m} active={selection?.kind === "member" && selection.id === m} icon={<UsersIcon />} onClick={() => onSelect({ kind: "member", id: m })}
            hint={p.characters.some((c) => c.id === m) ? "改过" : ""}>{p.characters.find((c) => c.id === m)?.name ?? ["", "车芸", "嬴诗", "桓远之"][m]}</Row>
        ))}
        <Row active={selection?.kind === "newgame"} icon={<SwordIcon />} onClick={() => onSelect({ kind: "newgame" })} hint={p.newGame ? "改过" : ""}>开局</Row>

        <Heading action={<AddButton label="新建 / 改技能" onClick={onAddSkill} />}>技能</Heading>
        {p.skills.map((s) => (
          <Row key={`s${s.local}`} active={selection?.kind === "skill" && selection.local === s.local} icon={<SparklesIcon />}
            onClick={() => onSelect({ kind: "skill", local: s.local })} hint="新">{s.name}</Row>
        ))}
        {p.skillEdits.map((s) => (
          <Row key={`e${s.id}`} active={selection?.kind === "skill_edit" && selection.id === s.id} icon={<SparklesIcon />}
            onClick={() => onSelect({ kind: "skill_edit", id: s.id })} hint="改原版">{s.name ?? gskills?.find((g) => g.id === s.id)?.name ?? `原版技能 ${s.id}`}</Row>
        ))}
        {p.skills.length === 0 && p.skillEdits.length === 0 && <p className="px-2 py-1 text-xs text-muted-foreground">复制原版技能做新招式，或者直接改原版技能（含绝技）的威力和消耗。</p>}

        <Heading>改过的原版</Heading>
        {p.overrides.map((o) => (
          <Row key={o.id} active={selection?.kind === "override" && selection.id === o.id} icon={<PencilIcon />}
            onClick={() => onSelect({ kind: "override", id: o.id })} hint={`${o.code.length} 条`}>#{o.id} {o.name}</Row>
        ))}
        {p.npcEdits.map((e) => (
          <Row key={`${e.map}:${e.actor}`} active={selection?.kind === "orig_npc" && selection.actor === e.actor && selection.map === e.map} icon={<UserIcon />}
            onClick={() => { onMap(e.map); onSelect({ kind: "orig_npc", map: e.map, actor: e.actor }) }} hint={e.remove ? "删掉" : "改过"}>
            {e.name ?? (names?.people[String(e.actor)] || `原版角色 ${e.actor}`)}</Row>
        ))}
        {p.overrides.length === 0 && p.npcEdits.length === 0 && (
          <p className="px-2 py-1 text-xs text-muted-foreground">切到上面的「原版」，选一个剧情事件点「复制到方案修改」；或在地图上点原版 NPC 修改。</p>
        )}

        <Heading action={<AddButton label="新建事件" onClick={onAddEvent} />}>事件</Heading>
        {p.events.map((e) => (
          <Row key={e.local} active={sel("event", e.local)} icon={<ListIcon />} onClick={() => onSelect({ kind: "event", local: e.local })}
            hint={`${e.blocks.length} 块`}>#{e.local} {e.name}</Row>
        ))}
        {p.events.length === 0 && <p className="px-2 py-1 text-xs text-muted-foreground">还没有事件。</p>}

        <Heading action={<AddButton label="新建任务" onClick={onAddQuest} />}>任务</Heading>
        {p.quests.map((q) => (
          <Row key={q.local} active={sel("quest", q.local)} icon={<ScrollTextIcon />} onClick={() => onSelect({ kind: "quest", local: q.local })}
            hint={q.main ? "主线" : "支线"}>{q.title}</Row>
        ))}
        {p.quests.length === 0 && <p className="px-2 py-1 text-xs text-muted-foreground">任务会出现在游戏「记载 · 事」页，可以分步骤接受、完成。</p>}

        <Heading action={<AddButton label="新建物品" onClick={onAddItem} />}>物品</Heading>
        {p.items.map((it) => (
          <Row key={it.local} active={sel("item", it.local)} icon={<ItemIcon icon={game?.find((g) => g.id === it.base)?.icon} className="size-4" />}
            onClick={() => onSelect({ kind: "item", local: it.local })} hint={`${it.price} 文`}>{it.name}</Row>
        ))}
        {p.items.length === 0 && <p className="px-2 py-1 text-xs text-muted-foreground">可以复制一件原版物品，改成自己的（例：回血更多的药）。</p>}

        <Heading action={<AddButton label="新建怪物" onClick={onAddMonster} />}>怪物</Heading>
        {p.monsters.map((m) => (
          <Row key={m.local} active={sel("monster", m.local)} icon={<PawPrintIcon />} onClick={() => onSelect({ kind: "monster", local: m.local })}
            hint={`${m.level} 级`}>{m.name}</Row>
        ))}
        {p.monsters.length === 0 && <p className="px-2 py-1 text-xs text-muted-foreground">可以复制一只原版怪物，改名字、数值和掉落。</p>}

        <Heading action={<AddButton label="新建战斗" onClick={onAddBattle} />}>战斗</Heading>
        {p.battles.map((b) => (
          <Row key={b.local} active={sel("battle", b.local)} icon={<SwordsIcon />} onClick={() => onSelect({ kind: "battle", local: b.local })}
            hint={`${b.enemies.length} 个敌人`}>{b.name}</Row>
        ))}
        {p.battles.length === 0 && <p className="px-2 py-1 text-xs text-muted-foreground">选一个原版战场，放上自己的怪物，在事件里用「开战」积木打。</p>}

        <Heading action={<AddButton label="新建变量" onClick={onAddVar} />}>变量</Heading>
        {p.vars.map((v) => (
          <Row key={v.local} active={sel("var", v.local)} icon={<HashIcon />} onClick={() => onSelect({ kind: "var", local: v.local })}>{v.name}</Row>
        ))}
        {p.vars.length === 0 && <p className="px-2 py-1 text-xs text-muted-foreground">变量是跟存档保存的计数器，例「打倒了几只山贼熊」。</p>}

        <Heading action={<AddButton label="新建旗标" onClick={onAddFlag} />}>旗标</Heading>
        {p.flags.map((f) => (
          <Row key={f.local} active={sel("flag", f.local)} icon={<FlagIcon />} onClick={() => onSelect({ kind: "flag", local: f.local })}>
            F{f.local} {f.name}
          </Row>
        ))}
        {p.flags.length === 0 && <p className="px-2 py-1 text-xs text-muted-foreground">还没有旗标。</p>}

        <Heading action={importing ? <Spinner className="mr-1.5 size-3.5" /> : <AddButton label="导入模型（.glb）" onClick={onImportModel} />}>模型</Heading>
        {p.models.map((m) => (
          <Row key={m.local} active={sel("model", m.local)} icon={<BoxIcon />} onClick={() => onSelect({ kind: "model", local: m.local })}
            hint={`${p.npcs.filter((n) => n.model === m.local).length + p.monsters.filter((x) => x.model === m.local).length} 处使用`}>{m.name}</Row>
        ))}
        {p.models.length === 0 && <p className="px-2 py-1 text-xs text-muted-foreground">NPC 默认用原版模型。也可以导入自己的 .glb 模型（点 + 或直接拖进窗口）。</p>}
      </div>
    </ScrollArea>
  )
}
