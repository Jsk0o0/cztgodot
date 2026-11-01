import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Checkbox } from "@/components/ui/checkbox"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Empty, EmptyDescription, EmptyHeader, EmptyTitle } from "@/components/ui/empty"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { FootprintsIcon, HashIcon, PlusIcon, Trash2Icon, XIcon } from "lucide-react"
import type { Encounter, MapDetail, ModVar, Project } from "@/lib/types"

/** 变量: 名字 + 用到它的地方 */
export function VarForm({ v, p, onChange, onDelete }: { v: ModVar; p: Project; onChange: (v: ModVar) => void; onDelete: () => void }) {
  const events = p.events.filter((e) => JSON.stringify(e.blocks).includes(`"var":${v.local}`)).map((e) => `事件「${e.name}」`)
  const monsters = p.monsters.filter((m) => m.counter === v.local).map((m) => `怪物「${m.name}」`)
  const uses = [...events, ...monsters]
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary"><HashIcon className="size-4" />变量 #{v.local}</div>
      <Field>
        <FieldLabel htmlFor="vname">名字</FieldLabel>
        <Input id="vname" value={v.name} onChange={(e) => onChange({ ...v, name: e.target.value })} />
        <FieldDescription>
          变量是一个跟着存档保存的数（0–65535），开始都是 0。可以在事件里「加上 / 设成」，用「如果变量」判断；
          怪物也可以设成「被打倒时这个变量 +1」，用来做「打倒 5 只山贼熊」这种任务。
        </FieldDescription>
      </Field>
      <p className="text-sm text-muted-foreground">{uses.length ? `用到它的：${uses.join("、")}` : "还没有地方用到它。"}</p>
      {uses.length === 0 && (
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button variant="ghost" size="sm" className="text-destructive"><Trash2Icon />删除这个变量</Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>删除变量「{v.name}」？</AlertDialogTitle>
              <AlertDialogDescription>玩家存档里记下的值不会再用到。</AlertDialogDescription>
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

/** 某张地图的遇敌: 原版遇敌区域 + 本 mod 加进去的战斗 (重复 = 权重, 同原版) */
export function EncounterForm({ map, detail, p, onChange }: { map: number; detail: MapDetail | null; p: Project; onChange: (list: Encounter[]) => void }) {
  const zones = detail?.id === map ? detail.zones ?? [] : []
  const mine = p.encounters.filter((e) => e.map === map)
  const others = p.encounters.filter((e) => e.map !== map)
  const set = (list: Encounter[]) => onChange([...others, ...list])
  const inZone = (e: Encounter, zi: number) => e.zones.length === 0 || e.zones.includes(zi)
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary"><FootprintsIcon className="size-4" />遇敌 · {detail?.title || detail?.name || map}</div>
      {zones.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyTitle>这张地图原版没有遇敌</EmptyTitle>
            <EmptyDescription>mod 战斗只能加进原版就会遇敌的地图（大地图、迷宫、野外）。</EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <FieldGroup>
          <Field>
            <FieldLabel>本 mod 加的遇敌战斗</FieldLabel>
            {mine.length === 0 && <p className="text-sm text-muted-foreground">还没有。加一场后，走在下面的区域里就有机会遇到它。</p>}
            <div className="space-y-3">
              {mine.map((e, i) => (
                <div key={i} className="space-y-2 rounded-md border p-2">
                  <div className="flex items-center gap-2 text-sm">
                    <Select value={String(e.battle)} onValueChange={(v) => set(mine.map((x, k) => (k === i ? { ...x, battle: Number(v) } : x)))}>
                      <SelectTrigger size="sm" className="min-w-0 flex-1"><SelectValue placeholder="选择战斗" /></SelectTrigger>
                      <SelectContent>{p.battles.map((b) => <SelectItem key={b.local} value={String(b.local)}>{b.name}</SelectItem>)}</SelectContent>
                    </Select>
                    权重
                    <Input type="number" min={1} max={20} value={e.weight} className="h-8 w-16"
                      onChange={(ev) => set(mine.map((x, k) => (k === i ? { ...x, weight: Math.min(20, Math.max(1, Math.round(Number(ev.target.value) || 1))) } : x)))} />
                    <Button variant="ghost" size="icon-sm" aria-label="去掉" onClick={() => set(mine.filter((_, k) => k !== i))}><XIcon /></Button>
                  </div>
                  <div className="flex flex-wrap gap-x-3 gap-y-1 text-xs">
                    {zones.map((_, zi) => (
                      <label key={zi} className="flex items-center gap-1.5">
                        <Checkbox checked={inZone(e, zi)} onCheckedChange={(v) => {
                          const cur = e.zones.length === 0 ? zones.map((_, k) => k) : e.zones
                          let nz = v ? [...new Set([...cur, zi])].sort((a, b) => a - b) : cur.filter((k) => k !== zi)
                          if (nz.length === zones.length) nz = []
                          if (nz.length === 0 && !v) return // 至少留一个区域
                          set(mine.map((x, k) => (k === i ? { ...x, zones: nz } : x)))
                        }} />
                        区域 {zi + 1}
                      </label>
                    ))}
                  </div>
                </div>
              ))}
            </div>
            <Button variant="outline" size="sm" className="w-fit" disabled={p.battles.length === 0}
              onClick={() => set([...mine, { map, battle: p.battles[0].local, weight: 3, zones: [] }])}><PlusIcon />加一场遇敌战斗</Button>
            {p.battles.length === 0 && <FieldDescription>先在左边「战斗」新建一场战斗。</FieldDescription>}
          </Field>
          <Field>
            <FieldLabel>原版遇敌区域</FieldLabel>
            <FieldDescription>走在区域里时按原版的概率遇敌，再从区域的战斗列表里随机挑一场；列表里出现几次就是几份机会。</FieldDescription>
            <div className="space-y-2">
              {zones.map((z, zi) => {
                const add = mine.filter((e) => inZone(e, zi)).reduce((n, e) => n + e.weight, 0)
                const total = z.battles.length + add
                const counts = new Map<string, number>()
                z.names.forEach((n) => counts.set(n, (counts.get(n) ?? 0) + 1))
                return (
                  <div key={zi} className="rounded-md border p-2 text-sm">
                    <div className="flex items-center justify-between">
                      <span className="font-medium">区域 {zi + 1}</span>
                      <span className="text-xs text-muted-foreground">{Math.round((z.max[0] - z.min[0]) / 100)} × {Math.round((z.max[1] - z.min[1]) / 100)} 米</span>
                    </div>
                    <div className="mt-1 flex flex-wrap gap-1">
                      {[...counts].map(([n, c]) => <Badge key={n} variant="secondary">{n}{c > 1 ? ` ·${c}` : ""}</Badge>)}
                    </div>
                    {add > 0 && <div className="mt-1 text-xs text-primary">遇敌时 {Math.round((add / total) * 100)}% 是本 mod 的战斗（{add} / {total} 份）</div>}
                  </div>
                )
              })}
            </div>
          </Field>
        </FieldGroup>
      )}
    </div>
  )
}
