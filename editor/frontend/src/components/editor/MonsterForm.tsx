import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Skeleton } from "@/components/ui/skeleton"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { ChevronsUpDownIcon, PawPrintIcon, Trash2Icon, TriangleAlertIcon } from "lucide-react"
import { ModelPreview } from "./ModelPreview"
import { ItemPicker } from "./ItemPicker"
import { api } from "@/lib/api"
import type { CustomModel, GameMonster, ModMonster, MonsterPose, MonsterStats, Project } from "@/lib/types"

// 原版怪物只读一次, 全编辑器共用
let cache: Promise<GameMonster[]> | null = null
export function useGameMonsters(): GameMonster[] | null {
  const [list, setList] = useState<GameMonster[] | null>(null)
  useEffect(() => {
    let alive = true
    cache ??= api.listMonsters().catch((e) => {
      cache = null
      throw e
    })
    cache.then((v) => alive && setList(v)).catch(() => alive && setList([]))
    return () => {
      alive = false
    }
  }, [])
  return list
}

export type MonsterRef = { monster?: number; modMonster?: number }

export function describeMonster(r: MonsterRef, p: Project, game: GameMonster[] | null): { name: string; level?: number; base?: GameMonster } {
  if (r.modMonster) {
    const m = p.monsters.find((x) => x.local === r.modMonster)
    return { name: m?.name ?? `（怪物 #${r.modMonster} 已删除）`, level: m?.level, base: game?.find((g) => g.id === m?.base) }
  }
  const g = game?.find((x) => x.id === r.monster)
  return { name: g?.name ?? (r.monster ? `原版怪物 ${r.monster}` : "选择怪物"), level: g?.level, base: g }
}

/** 怪物列表 (可搜索): 本 mod 怪物在最上面, 原版按图鉴种族分组, 首领单独一组 */
export function MonsterList({ p, game, onPick, mod = true, selected }: {
  p: Project; game: GameMonster[] | null; onPick: (r: MonsterRef) => void; mod?: boolean; selected?: MonsterRef
}) {
  if (game === null) {
    return <div className="space-y-2 p-3">{[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-7 w-full" />)}</div>
  }
  const isSel = (r: MonsterRef) => !!selected && (r.modMonster ? selected.modMonster === r.modMonster : !selected.modMonster && selected.monster === r.monster)
  const races = [...new Set(game.filter((g) => !g.boss).map((g) => g.race || "其他"))]
  const groups: [string, GameMonster[]][] = [...races.map((r) => [r, game.filter((g) => !g.boss && (g.race || "其他") === r)] as [string, GameMonster[]]),
    ["首领", game.filter((g) => g.boss)]]
  return (
    <Command filter={(value, search) => (value.toLowerCase().includes(search.toLowerCase()) ? 1 : 0)}>
      <CommandInput placeholder="搜索怪物名或编号…" />
      <CommandList className="max-h-80">
        <CommandEmpty>找不到这个怪物</CommandEmpty>
        {mod && p.monsters.length > 0 && (
          <CommandGroup heading="本 mod 的怪物">
            {p.monsters.map((m) => (
              <CommandItem key={`m${m.local}`} value={`mod ${m.local} ${m.name}`} onSelect={() => onPick({ modMonster: m.local })} data-checked={isSel({ modMonster: m.local })}>
                <PawPrintIcon />
                <span className="flex-1 truncate">{m.name}</span>
                <span className="text-xs text-muted-foreground">{m.level} 级 · @monster:{m.local}</span>
              </CommandItem>
            ))}
          </CommandGroup>
        )}
        {groups.map(([race, list]) => list.length > 0 && (
          <CommandGroup key={race} heading={`原版 · ${race}`}>
            {list.map((g) => (
              <CommandItem key={g.id} value={`${g.id} ${g.name}`} onSelect={() => onPick({ monster: g.id })} data-checked={isSel({ monster: g.id })}>
                <span className="flex-1 truncate">{g.name}</span>
                <span className="text-xs text-muted-foreground">{g.id} · {g.level} 级 · 生命 {g.hp}</span>
              </CommandItem>
            ))}
          </CommandGroup>
        ))}
      </CommandList>
    </Command>
  )
}

/** 选怪物的按钮 (弹出可搜索列表) */
export function MonsterPicker({ p, value, onChange, className = "" }: { p: Project; value: MonsterRef; onChange: (r: MonsterRef) => void; className?: string }) {
  const game = useGameMonsters()
  const [open, setOpen] = useState(false)
  const d = describeMonster(value, p, game)
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm" className={`h-8 justify-between gap-2 font-normal ${className}`}>
          <span className="truncate">{d.name}{d.level ? <span className="ml-1.5 text-xs text-muted-foreground">{d.level} 级</span> : null}</span>
          <ChevronsUpDownIcon className="opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80 p-0" align="start">
        <MonsterList p={p} game={game} selected={value} onPick={(r) => { onChange(r); setOpen(false) }} />
      </PopoverContent>
    </Popover>
  )
}

const STATS: [keyof MonsterStats, string][] = [
  ["level", "等级"], ["hp", "生命"], ["mp", "灵力"], ["sp", "体力"],
  ["atk", "攻击"], ["def", "防御"], ["spd", "速度"], ["matk", "仙攻"],
  ["mdef", "仙防"], ["hit", "命中"], ["eva", "闪避"], ["mhit", "仙术命中"], ["meva", "仙术闪避"],
]

/** 数值提示: 和复制来源的原版怪物比, 偏离太多时提醒 (只是提醒, 不拦) */
function warnings(m: ModMonster, base?: GameMonster): string[] {
  if (!base) return []
  const out: string[] = []
  for (const [k, label] of [["hp", "生命"], ["atk", "攻击"], ["def", "防御"], ["matk", "仙攻"]] as const) {
    const b = base[k], v = m[k]
    if (b > 0 && v >= b * 4) out.push(`${label} ${v} 是原版「${base.name}」的 ${(v / b).toFixed(1)} 倍`)
    if (b > 0 && v * 4 <= b) out.push(`${label} ${v} 不到原版「${base.name}」的四分之一`)
  }
  if (base.exp > 0 && m.exp >= base.exp * 5) out.push(`经验 ${m.exp} 是原版的 ${(m.exp / base.exp).toFixed(1)} 倍，升级会很快`)
  return out
}

// 选了模型后先按动画名猜一个对应 (只是编辑器的建议, 作者可改): 关键字按顺序找第一个包含它的动画
const GUESS: [(p: MonsterPose) => boolean, string[]][] = [
  [(p) => p.q === 14, []],
  [(p) => p.q === 25 || p.q === 24, ["hurt", "dmag", "hit", "damage"]],
  [(p) => p.q === 26, ["die", "death", "down"]],
  [(p) => p.q === 35, ["win", "victory", "hello", "cheer"]],
  [(p) => p.uses.some((u) => u.endsWith("（移动）")), ["run", "walk"]],
  [(p) => p.uses.some((u) => u.startsWith("普攻")), ["handatk", "attack", "atk", "fight"]],
  [(p) => p.uses.some((u) => u.startsWith("技能")), ["fmag", "mag", "skill", "cast", "spell", "atk"]],
]
function guessPoses(cm: CustomModel, poses: MonsterPose[]): Record<string, string> {
  const out: Record<string, string> = { "14": cm.idle || cm.anims[0]?.name || "" }
  for (const p of poses) {
    if (p.q === 14) continue
    const rule = GUESS.find(([f]) => f(p))
    const keys = rule?.[1] ?? []
    const hit = keys.map((k) => cm.anims.find((a) => a.name.toLowerCase().includes(k))).find(Boolean)
    if (hit) out[String(p.q)] = hit.name
  }
  return out
}

/** 战斗模型: 原版模型, 或本 mod 的自定义模型 + 每个战斗动作配一个动画 */
function BattleModel({ m, p, base, onChange }: { m: ModMonster; p: Project; base?: GameMonster; onChange: (m: ModMonster) => void }) {
  const cm = p.models.find((x) => x.local === m.model)
  const [focus, setFocus] = useState(14)
  const poses = base?.poses ?? []
  const clipOf = (q: number) => m.poses?.[String(q)] || ""
  const shown = clipOf(focus) || clipOf(14)
  return (
    <Field>
      <FieldLabel>战斗模型</FieldLabel>
      <Select value={String(m.model ?? 0)} onValueChange={(v) => {
        const local = Number(v)
        const nm = p.models.find((x) => x.local === local)
        onChange({ ...m, model: local || undefined, poses: nm ? guessPoses(nm, poses) : undefined })
      }}>
        <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value="0">原版「{base?.name ?? m.base}」的模型</SelectItem>
          {p.models.map((x) => <SelectItem key={x.local} value={String(x.local)}>自定义：{x.name}</SelectItem>)}
        </SelectContent>
      </Select>
      {p.models.length === 0 && <FieldDescription>想换模型，先在左边「模型」导入带动画的 .glb。</FieldDescription>}
      {cm && (
        <>
          <ModelPreview url={`/project/${cm.file}`} scale={cm.scale} yaw={cm.yaw} anim={shown} ground={cm.ground ?? 0} />
          <div className="divide-y rounded-md border">
            {poses.map((ps) => (
              <div key={ps.q} className={`flex items-center gap-2 px-2 py-1.5 text-sm ${focus === ps.q ? "bg-accent/40" : ""}`} onClick={() => setFocus(ps.q)}>
                <div className="min-w-0 flex-1">
                  <div className="truncate">{ps.uses.join("、")}</div>
                  <div className="text-xs text-muted-foreground">
                    动作 {ps.q} · {(ps.ticks / 35).toFixed(1)} 秒{ps.loop ? " · 循环" : ""}{ps.hits ? ` · 命中 ${ps.hits} 次` : ""}
                  </div>
                </div>
                <Select value={clipOf(ps.q) || "-"} onValueChange={(v) => { setFocus(ps.q); onChange({ ...m, poses: { ...m.poses, [String(ps.q)]: v === "-" ? "" : v } }) }}>
                  <SelectTrigger size="sm" className="w-40"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {ps.q !== 14 && <SelectItem value="-">（用待机动画）</SelectItem>}
                    {cm.anims.map((a) => <SelectItem key={a.name} value={a.name}>{a.name} · {a.seconds.toFixed(1)} 秒</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            ))}
          </div>
          <FieldDescription>
            每个动作的时长、命中时刻、音效和位移都照抄原版「{base?.name}」，不循环的动作会把动画拉伸到原版时长。
            模型里如果有 markerN_ 开头的骨骼，会当成特效挂点；没有就从怪物位置放特效。
          </FieldDescription>
        </>
      )}
    </Field>
  )
}

export function MonsterForm({ m, p, onChange, onDelete }: { m: ModMonster; p: Project; onChange: (m: ModMonster) => void; onDelete: () => void }) {
  const game = useGameMonsters()
  const base = game?.find((g) => g.id === m.base)
  const uses = p.battles.filter((b) => b.enemies.some((e) => e.modMonster === m.local)).map((b) => b.name)
  const warn = warnings(m, base)
  const num = (v: string, min = 0) => Math.max(min, Math.round(Number(v) || 0))
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary"><PawPrintIcon className="size-4" />怪物 @monster:{m.local}</div>
      {base?.glb && !m.model && <ModelPreview url={`/gamedata/${base.glb}`} scale={base.scale} yaw={0} anim="pose_80" />}
      <div className="flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
        复制自原版「{base?.name ?? m.base}」<Badge variant="secondary">{base?.race || "?"}</Badge>
        {base?.boss && <Badge variant="secondary">首领</Badge>}
      </div>
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="mname">名字</FieldLabel>
          <Input id="mname" value={m.name} onChange={(e) => onChange({ ...m, name: e.target.value })} />
        </Field>
        <Field>
          <FieldLabel htmlFor="mdesc">图鉴说明</FieldLabel>
          <Textarea id="mdesc" rows={2} value={m.desc} onChange={(e) => onChange({ ...m, desc: e.target.value })} />
          <FieldDescription>打过以后出现在游戏「记载 · 人」页。</FieldDescription>
        </Field>
        <Field>
          <FieldLabel>数值</FieldLabel>
          <div className="grid grid-cols-2 gap-x-3 gap-y-2">
            {STATS.map(([k, label]) => (
              <label key={k} className="grid grid-cols-[4.5rem_1fr] items-center gap-2 text-sm">
                <span>{label}</span>
                <Input type="number" min={k === "level" || k === "hp" ? 1 : 0} value={m[k]} className="h-8" title={base ? `原版 ${base[k]}` : undefined}
                  onChange={(e) => onChange({ ...m, [k]: num(e.target.value, k === "level" || k === "hp" ? 1 : 0) })} />
              </label>
            ))}
          </div>
          <FieldDescription>普攻、技能、AI、五行抗性{m.model ? "" : "和模型"}都照抄原版「{base?.name}」。</FieldDescription>
        </Field>
        <BattleModel m={m} p={p} base={base} onChange={onChange} />
        {warn.length > 0 && (
          <Alert>
            <TriangleAlertIcon />
            <AlertDescription><ul className="list-disc pl-4">{warn.map((w) => <li key={w}>{w}</li>)}</ul></AlertDescription>
          </Alert>
        )}
        <Field>
          <FieldLabel>打倒后</FieldLabel>
          <div className="grid grid-cols-2 gap-x-3 gap-y-2">
            <label className="grid grid-cols-[4.5rem_1fr] items-center gap-2 text-sm"><span>经验</span>
              <Input type="number" min={0} value={m.exp} className="h-8" onChange={(e) => onChange({ ...m, exp: num(e.target.value) })} /></label>
            <label className="grid grid-cols-[4.5rem_1fr] items-center gap-2 text-sm"><span>金钱</span>
              <Input type="number" min={0} value={m.money} className="h-8" onChange={(e) => onChange({ ...m, money: num(e.target.value) })} /></label>
          </div>
          <div className="mt-2 flex items-center gap-2 text-sm">
            <span className="w-[4.5rem] shrink-0">掉落</span>
            <ItemPicker p={p} value={{ item: m.dropItem, modItem: m.dropModItem }} className="min-w-0 flex-1"
              onChange={(r) => onChange({ ...m, dropItem: r.item, dropModItem: r.modItem, dropRate: m.dropRate || 100 })} />
            <Input type="number" min={0} max={100} value={m.dropRate} className="h-8 w-20"
              onChange={(e) => onChange({ ...m, dropRate: Math.min(100, num(e.target.value)) })} />
            <span className="text-muted-foreground">%</span>
          </div>
          <FieldDescription>每只倒下时按几率掉落（同原版）；战斗里每个队员都拿全额经验。</FieldDescription>
          <div className="mt-2 flex items-center gap-2 text-sm">
            <span className="w-[4.5rem] shrink-0">计数</span>
            <Select value={String(m.counter ?? 0)} onValueChange={(v) => onChange({ ...m, counter: Number(v) || undefined })}>
              <SelectTrigger size="sm" className="min-w-0 flex-1"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="0">不计数</SelectItem>
                {p.vars.map((x) => <SelectItem key={x.local} value={String(x.local)}>被打倒时「{x.name}」+1</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <FieldDescription>本 mod 的怪物不能被收化。</FieldDescription>
        </Field>
      </FieldGroup>
      {uses.length > 0 ? (
        <p className="text-xs text-muted-foreground">正在被战斗 {uses.map((n) => `「${n}」`).join("、")} 使用，先从战斗里去掉才能删除。</p>
      ) : (
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button variant="ghost" size="sm" className="text-destructive"><Trash2Icon />删除这个怪物</Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>删除怪物「{m.name}」？</AlertDialogTitle>
              <AlertDialogDescription>图鉴里已经记下的这只怪物不会再显示。</AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>取消</AlertDialogCancel>
              <AlertDialogAction onClick={onDelete}>删除</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      )}
    </div>
  )
}

/** 新建怪物: 先选一只原版怪物当底子 */
export function NewMonsterDialog({ open, onOpenChange, p, onCreate }: {
  open: boolean; onOpenChange: (v: boolean) => void; p: Project; onCreate: (base: GameMonster) => void
}) {
  const game = useGameMonsters()
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md p-0">
        <DialogHeader className="px-4 pt-4">
          <DialogTitle>新建怪物</DialogTitle>
          <DialogDescription>先选一只原版怪物当底子：模型、普攻、技能和 AI 都照抄它，再改名字、数值和掉落。</DialogDescription>
        </DialogHeader>
        <div className="border-t">
          <MonsterList p={p} game={game} mod={false} onPick={(r) => {
            const g = game?.find((x) => x.id === r.monster)
            if (g) { onCreate(g); onOpenChange(false) }
          }} />
        </div>
      </DialogContent>
    </Dialog>
  )
}
