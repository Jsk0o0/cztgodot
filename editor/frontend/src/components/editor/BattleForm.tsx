import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Checkbox } from "@/components/ui/checkbox"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Skeleton } from "@/components/ui/skeleton"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { SwordsIcon, Trash2Icon } from "lucide-react"
import { MonsterPicker, describeMonster, useGameMonsters } from "./MonsterForm"
import { api } from "@/lib/api"
import type { GameBattlefield, ModBattle, Project } from "@/lib/types"

let cache: Promise<GameBattlefield[]> | null = null
export function useBattlefields(): GameBattlefield[] | null {
  const [list, setList] = useState<GameBattlefield[] | null>(null)
  useEffect(() => {
    let alive = true
    cache ??= api.listBattlefields().catch((e) => {
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

// 我方站位 (同游戏 battle.gd PARTY_POS: 车芸 / 嬴诗 / 桓远之), 俯视图里画出来方便对照
const PARTY = [[-275, -390], [-65, -340], [100, -400]]

/** 战场俯视图: 下方我方三人, 上方敌人站位 (编号同列表) */
function SlotMap({ bf, used }: { bf: GameBattlefield; used: Set<number> }) {
  const pts = [...PARTY, ...bf.slots.map((s) => [s.pos[0], s.pos[2]])]
  const pad = 80
  const xs = pts.map((p) => p[0]), zs = pts.map((p) => p[1])
  const x0 = Math.min(...xs) - pad, x1 = Math.max(...xs) + pad, z0 = Math.min(...zs) - pad, z1 = Math.max(...zs) + pad
  // 原版是左手坐标: 画面上 x 向右, z 向上 (敌人在远处)
  const W = 280, H = Math.max(140, Math.min(220, (W * (z1 - z0)) / (x1 - x0)))
  const sx = (x: number) => ((x - x0) / (x1 - x0)) * W
  const sz = (z: number) => H - ((z - z0) / (z1 - z0)) * H
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full rounded-md border bg-muted/30">
      {PARTY.map(([x, z], i) => <circle key={`p${i}`} cx={sx(x)} cy={sz(z)} r={7} className="fill-sky-500/60" />)}
      {bf.slots.map((s, i) => (
        <g key={i}>
          <circle cx={sx(s.pos[0])} cy={sz(s.pos[2])} r={11} className={used.has(i) ? "fill-primary" : "fill-none stroke-muted-foreground"} strokeDasharray="3 2" />
          <text x={sx(s.pos[0])} y={sz(s.pos[2]) + 4} textAnchor="middle" className={`text-[11px] ${used.has(i) ? "fill-primary-foreground" : "fill-muted-foreground"}`}>{i + 1}</text>
        </g>
      ))}
      <text x={6} y={H - 6} className="fill-muted-foreground text-[10px]">蓝点 = 我方</text>
    </svg>
  )
}

/** 原版普通战场列表 (可搜索) */
function BattlefieldList({ list, onPick, selected }: { list: GameBattlefield[] | null; onPick: (b: GameBattlefield) => void; selected?: number }) {
  if (list === null) return <div className="space-y-2 p-3">{[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-7 w-full" />)}</div>
  return (
    <Command filter={(value, search) => (value.toLowerCase().includes(search.toLowerCase()) ? 1 : 0)}>
      <CommandInput placeholder="搜索地点、怪物名或编号…" />
      <CommandList className="max-h-96">
        <CommandEmpty>找不到这个战场</CommandEmpty>
        <CommandGroup heading="原版普通战场（没有剧情对白的）">
          {list.map((b) => (
            <CommandItem key={b.id} value={`${b.id} ${b.name} ${b.slots.map((s) => s.name).join(" ")}`} onSelect={() => onPick(b)} data-checked={selected === b.id}>
              <div className="min-w-0 flex-1">
                <div className="truncate">{b.name.replace(/_\d+$/, "")}</div>
                <div className="truncate text-xs text-muted-foreground">{b.slots.map((s) => s.name).join("、")}</div>
              </div>
              <span className="text-xs text-muted-foreground">#{b.id} · {b.slots.length} 位</span>
            </CommandItem>
          ))}
        </CommandGroup>
      </CommandList>
    </Command>
  )
}

export function BattleForm({ b, p, onChange, onDelete }: { b: ModBattle; p: Project; onChange: (b: ModBattle) => void; onDelete: () => void }) {
  const list = useBattlefields()
  const game = useGameMonsters()
  const [pick, setPick] = useState(false)
  const bf = list?.find((x) => x.id === b.base)
  const uses = p.events.filter((e) => JSON.stringify(e.blocks).includes(`"battle":${b.local}`)).map((e) => e.name)
  const used = new Set(b.enemies.map((e) => e.at))
  const setSlot = (at: number, on: boolean) => {
    const rest = b.enemies.filter((e) => e.at !== at)
    onChange({ ...b, enemies: on ? [...rest, { at, monster: bf?.slots[at]?.monster }].sort((x, y) => x.at - y.at) : rest })
  }
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary"><SwordsIcon className="size-4" />战斗 @battle:{b.local}</div>
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="bname">名字</FieldLabel>
          <Input id="bname" value={b.name} onChange={(e) => onChange({ ...b, name: e.target.value })} />
          <FieldDescription>只在编辑器里显示，方便在「开战」积木里选。</FieldDescription>
        </Field>
        <Field>
          <FieldLabel>战场</FieldLabel>
          {list === null ? <Skeleton className="h-9 w-full" /> : (
            <div className="flex items-center gap-2">
              <div className="min-w-0 flex-1 text-sm">
                <div className="truncate">{bf ? bf.name.replace(/_\d+$/, "") : `原版战场 ${b.base}`}</div>
                <div className="text-xs text-muted-foreground">#{b.base} · {bf?.scene}</div>
              </div>
              <Button variant="outline" size="sm" onClick={() => setPick(true)}>换战场</Button>
            </div>
          )}
          <FieldDescription>场景、镜头、开场演出和战斗音乐都照抄这个原版战场；剧情战一样，输了回标题。</FieldDescription>
        </Field>
        {bf && (
          <Field>
            <FieldLabel>敌人站位</FieldLabel>
            <SlotMap bf={bf} used={used} />
            <div className="space-y-1.5">
              {bf.slots.map((s, i) => {
                const e = b.enemies.find((x) => x.at === i)
                return (
                  <div key={i} className="flex items-center gap-2 text-sm">
                    <Checkbox checked={!!e} onCheckedChange={(v) => setSlot(i, !!v)} aria-label={`站位 ${i + 1}`} />
                    <span className="shrink-0 whitespace-nowrap text-muted-foreground">位置 {i + 1}</span>
                    {e ? (
                      <MonsterPicker p={p} value={{ monster: e.monster, modMonster: e.modMonster }} className="min-w-0 flex-1"
                        onChange={(r) => onChange({ ...b, enemies: b.enemies.map((x) => (x.at === i ? { at: i, ...r } : x)) })} />
                    ) : (
                      <span className="flex-1 text-xs text-muted-foreground">空（原版是「{s.name}」）</span>
                    )}
                  </div>
                )
              })}
            </div>
            <FieldDescription>位置和朝向用原版战场的；至少放一个敌人。</FieldDescription>
          </Field>
        )}
        {b.enemies.length > 0 && game && (
          <div className="flex flex-wrap gap-1.5">
            {b.enemies.map((e) => {
              const d = describeMonster(e, p, game)
              return <Badge key={e.at} variant="secondary">{e.at + 1}. {d.name}{d.level ? ` ${d.level} 级` : ""}</Badge>
            })}
          </div>
        )}
      </FieldGroup>
      {uses.length > 0 ? (
        <p className="text-xs text-muted-foreground">正在被事件 {uses.map((n) => `「${n}」`).join("、")} 使用，先从积木里去掉才能删除。</p>
      ) : (
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button variant="ghost" size="sm" className="text-destructive"><Trash2Icon />删除这场战斗</Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>删除战斗「{b.name}」？</AlertDialogTitle>
              <AlertDialogDescription>这场战斗的设置会丢失。</AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>取消</AlertDialogCancel>
              <AlertDialogAction onClick={onDelete}>删除</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      )}
      <Dialog open={pick} onOpenChange={setPick}>
        <DialogContent className="max-w-md p-0">
          <DialogHeader className="px-4 pt-4">
            <DialogTitle>换战场</DialogTitle>
            <DialogDescription>换了以后敌人恢复成原版那场的配置，再自己替换。</DialogDescription>
          </DialogHeader>
          <div className="border-t">
            <BattlefieldList list={list} selected={b.base} onPick={(x) => {
              onChange({ ...b, base: x.id, enemies: x.slots.map((s, i) => ({ at: i, monster: s.monster })) })
              setPick(false)
            }} />
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

/** 新建战斗: 先选一个原版普通战场当底子 (敌人先照原版放好) */
export function NewBattleDialog({ open, onOpenChange, onCreate }: { open: boolean; onOpenChange: (v: boolean) => void; onCreate: (bf: GameBattlefield) => void }) {
  const list = useBattlefields()
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md p-0">
        <DialogHeader className="px-4 pt-4">
          <DialogTitle>新建战斗</DialogTitle>
          <DialogDescription>先选一个原版战场：场景、镜头和开场演出照抄它，敌人先按原版放好，再换成自己的怪物。</DialogDescription>
        </DialogHeader>
        <div className="border-t">
          <BattlefieldList list={list} onPick={(x) => { onCreate(x); onOpenChange(false) }} />
        </div>
      </DialogContent>
    </Dialog>
  )
}
