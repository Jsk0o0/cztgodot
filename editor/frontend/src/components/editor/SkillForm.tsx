import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Skeleton } from "@/components/ui/skeleton"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { ChevronsUpDownIcon, RotateCcwIcon, SparklesIcon, Trash2Icon } from "lucide-react"
import { api } from "@/lib/api"
import type { GameSkill, ModSkill, Project, SkillEdit, SkillRef } from "@/lib/types"

let cache: Promise<GameSkill[]> | null = null
export function useGameSkills(): GameSkill[] | null {
  const [list, setList] = useState<GameSkill[] | null>(null)
  useEffect(() => {
    let alive = true
    cache ??= api.listSkills().catch((e) => { cache = null; throw e })
    cache.then((v) => alive && setList(v)).catch(() => alive && setList([]))
    return () => { alive = false }
  }, [])
  return list
}

export const MEMBER_NAMES: Record<number, string> = { 1: "车芸", 2: "嬴诗", 3: "桓远之" }

export function skillName(r: SkillRef, p: Project, game: GameSkill[] | null): string {
  if (r.modSkill) return p.skills.find((s) => s.local === r.modSkill)?.name ?? `（技能 #${r.modSkill} 已删除）`
  if (!r.skill) return "（不学）"
  const g = game?.find((s) => s.id === r.skill)
  return p.skillEdits.find((e) => e.id === r.skill)?.name ?? g?.name ?? `技能 ${r.skill}`
}

/** 消耗编码 (同物品恢复量 / 游戏 Formula.amount): ≤10000 定值, 10001–10099 百分比 */
export function costText(c: Record<string, number> | null | undefined): string {
  if (!c) return ""
  const f = (v: number) => (v > 10000 && v < 10100 ? `${v - 10000}%` : String(v))
  const parts: string[] = []
  if (c.mp) parts.push(`灵力 ${f(c.mp)}`)
  if (c.sp) parts.push(`体力 ${f(c.sp)}`)
  if (c.hp) parts.push(`生命 ${f(c.hp)}`)
  if (c.juji) parts.push(`绝技值 ${c.juji}`)
  return parts.join(" · ")
}

/** 技能列表 (可搜索): 本方案的在上, 原版按 谁会 分组 */
export function SkillList({ p, game, onPick, onlyCopy = false, allowNone = false }: {
  p: Project; game: GameSkill[] | null; onPick: (r: SkillRef) => void; onlyCopy?: boolean; allowNone?: boolean
}) {
  if (!game) return <div className="space-y-2 p-3">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-7 w-full" />)}</div>
  const list = onlyCopy ? game.filter((g) => g.copy) : game
  const groups: [string, GameSkill[]][] = [1, 2, 3].map((m) => [`原版 · ${MEMBER_NAMES[m]}的`, list.filter((g) => g.owner === m)] as [string, GameSkill[]])
  groups.push(["原版 · 敌人 / 其他", list.filter((g) => !g.owner)])
  return (
    <Command filter={(value, search) => (value.toLowerCase().includes(search.toLowerCase()) ? 1 : 0)}>
      <CommandInput placeholder="搜技能名、分类或编号…" />
      <CommandList className="max-h-80">
        <CommandEmpty>没有这个技能</CommandEmpty>
        {allowNone && <CommandGroup><CommandItem value="不学" onSelect={() => onPick({})}>（这一级不学技能）</CommandItem></CommandGroup>}
        {!onlyCopy && p.skills.length > 0 && (
          <CommandGroup heading="本方案的技能">
            {p.skills.map((s) => (
              <CommandItem key={`m${s.local}`} value={`mod ${s.local} ${s.name}`} onSelect={() => onPick({ modSkill: s.local })}>
                <SparklesIcon /><span className="flex-1 truncate">{s.name}</span><span className="text-xs text-muted-foreground">@skill:{s.local}</span>
              </CommandItem>
            ))}
          </CommandGroup>
        )}
        {groups.map(([h, l]) => l.length > 0 && (
          <CommandGroup key={h} heading={h}>
            {l.map((g) => (
              <CommandItem key={g.id} value={`${g.id} ${g.name} ${g.cat} ${g.note}`} onSelect={() => onPick({ skill: g.id })}>
                <span className="flex-1 truncate">{g.name}</span>
                <span className="text-xs text-muted-foreground">{g.cat} · {g.note || costText(g.cost)}</span>
              </CommandItem>
            ))}
          </CommandGroup>
        ))}
      </CommandList>
    </Command>
  )
}

export function SkillPicker({ p, value, onChange, allowNone = false, className = "" }: {
  p: Project; value: SkillRef; onChange: (r: SkillRef) => void; allowNone?: boolean; className?: string
}) {
  const game = useGameSkills()
  const [open, setOpen] = useState(false)
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm" className={`h-7 justify-between gap-1 px-2 font-normal ${className}`}>
          <span className="truncate">{skillName(value, p, game)}</span><ChevronsUpDownIcon className="opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-96 p-0" align="start">
        <SkillList p={p} game={game} allowNone={allowNone} onPick={(r) => { onChange(r); setOpen(false) }} />
      </PopoverContent>
    </Popover>
  )
}

const COSTS: [string, string][] = [["mp", "灵力"], ["sp", "体力"], ["hp", "生命"], ["juji", "绝技值"]]

/** 消耗: 四项, 定值或百分比 (编码同游戏: 10001–10099 = 百分比) */
function CostEditor({ cost, onChange }: { cost: Record<string, number>; onChange: (c: Record<string, number>) => void }) {
  return (
    <div className="grid grid-cols-2 gap-2">
      {COSTS.map(([k, label]) => {
        const v = cost[k] ?? 0
        const pct = v > 10000 && v < 10100
        return (
          <label key={k} className="flex items-center gap-1.5 text-sm">
            <span className="w-12 shrink-0">{label}</span>
            <Input type="number" min={0} className="h-8" value={pct ? v - 10000 : v}
              onChange={(e) => { const n = Math.max(0, Math.round(Number(e.target.value) || 0)); onChange({ ...cost, [k]: pct ? 10000 + Math.min(99, n) : n }) }} />
            {k !== "juji" && (
              <Button variant={pct ? "secondary" : "ghost"} size="sm" className="h-8 px-2" title="切换定值 / 百分比"
                onClick={() => onChange({ ...cost, [k]: pct ? v - 10000 : 10000 + Math.min(99, Math.max(1, v)) })}>{pct ? "%" : "点"}</Button>
            )}
          </label>
        )
      })}
    </div>
  )
}

/** 新技能 (复制原版) 或 改原版技能 */
export function SkillForm({ s, edit, p, onChange, onEdit, onDelete }: {
  s?: ModSkill; edit?: SkillEdit; p: Project
  onChange?: (s: ModSkill) => void; onEdit?: (e: SkillEdit | null) => void; onDelete?: () => void
}) {
  const game = useGameSkills()
  const base = game?.find((g) => g.id === (s ? s.base : edit?.id))
  const users = s ? p.characters.filter((c) => JSON.stringify(c.growth ?? []).includes(`"modSkill":${s.local}`)).length
    + (JSON.stringify(p.newGame?.skills ?? {}).includes(`"modSkill":${s.local}`) ? 1 : 0) : 0
  const name = s ? s.name : edit?.name ?? base?.name ?? ""
  const desc = s ? s.desc : edit?.desc ?? base?.desc ?? ""
  const power = s ? s.power : edit?.power ?? base?.power ?? 0
  const cost = s ? s.cost : { ...(base?.cost ?? {}), ...(edit?.cost ?? {}) }
  const set = (patch: Partial<ModSkill & SkillEdit>) => {
    if (s && onChange) onChange({ ...s, ...patch } as ModSkill)
    else if (edit && onEdit) onEdit({ ...edit, ...patch } as SkillEdit)
  }
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary">
        <SparklesIcon className="size-4" />{s ? `技能 @skill:${s.local}` : `改原版技能 #${edit?.id}`}
      </div>
      <div className="flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
        {s ? `复制自原版「${base?.name ?? s.base}」` : "原版技能"}
        {base && <Badge variant="secondary">{base.cat}</Badge>}
        {base?.note && <Badge variant="outline">{base.note}</Badge>}
        {base?.owner ? <Badge variant="outline">原版{MEMBER_NAMES[base.owner]}会</Badge> : null}
      </div>
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="skn">名字</FieldLabel>
          <Input id="skn" value={name} onChange={(e) => set({ name: e.target.value })} />
        </Field>
        <Field>
          <FieldLabel htmlFor="skd">说明</FieldLabel>
          <Textarea id="skd" rows={2} value={desc} onChange={(e) => set({ desc: e.target.value })} />
        </Field>
        <Field>
          <FieldLabel htmlFor="skp">威力</FieldLabel>
          <Input id="skp" type="number" min={0} value={power} onChange={(e) => set({ power: Math.max(0, Math.round(Number(e.target.value) || 0)) })} />
          <FieldDescription>原版「{base?.name}」是 {base?.power ?? "?"}。伤害公式同原版（攻击力和威力一起算）。</FieldDescription>
        </Field>
        <Field>
          <FieldLabel>消耗</FieldLabel>
          <CostEditor cost={cost} onChange={(c) => set({ cost: c })} />
          <FieldDescription>绝技（消耗绝技值的）也在这里改。原版：{costText(base?.cost) || "不消耗"}。</FieldDescription>
        </Field>
        <FieldDescription>招式演出、攻击范围、属性和附带状态都照抄原版「{base?.name}」。</FieldDescription>
      </FieldGroup>
      {s ? (users > 0 ? <p className="text-xs text-muted-foreground">有队员会学这个技能（成长表或开局），先去掉才能删除。</p> : (
        <AlertDialog>
          <AlertDialogTrigger asChild><Button variant="ghost" size="sm" className="text-destructive"><Trash2Icon />删除这个技能</Button></AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader><AlertDialogTitle>删除技能「{s.name}」？</AlertDialogTitle><AlertDialogDescription>存档里已经学会的会失效。</AlertDialogDescription></AlertDialogHeader>
            <AlertDialogFooter><AlertDialogCancel>取消</AlertDialogCancel><AlertDialogAction onClick={onDelete}>删除</AlertDialogAction></AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      )) : (
        <Button variant="outline" size="sm" className="w-full" onClick={() => onEdit?.(null)}><RotateCcwIcon />恢复原版</Button>
      )}
    </div>
  )
}

/** 新建技能: 复制一个原版技能, 或者直接改原版技能 */
export function NewSkillDialog({ open, onOpenChange, p, onCopy, onEditOrig }: {
  open: boolean; onOpenChange: (v: boolean) => void; p: Project; onCopy: (g: GameSkill) => void; onEditOrig: (g: GameSkill) => void
}) {
  const game = useGameSkills()
  const [mode, setMode] = useState<"copy" | "edit">("copy")
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md p-0">
        <DialogHeader className="px-4 pt-4">
          <DialogTitle>技能</DialogTitle>
          <DialogDescription>
            <span className="mb-2 flex gap-2">
              <Button size="sm" variant={mode === "copy" ? "default" : "outline"} onClick={() => setMode("copy")}>复制成新技能</Button>
              <Button size="sm" variant={mode === "edit" ? "default" : "outline"} onClick={() => setMode("edit")}>改原版技能</Button>
            </span>
            {mode === "copy" ? "选一个原版技能当底子：演出、范围、属性照抄，再改名字、威力和消耗。修复 / 木甲术有专门的逻辑，不能复制。"
              : "直接改原版技能的名字、威力、消耗（包括绝技）。"}
          </DialogDescription>
        </DialogHeader>
        <div className="border-t">
          <SkillList p={p} game={game} onlyCopy={mode === "copy"} onPick={(r) => {
            const g = game?.find((x) => x.id === r.skill)
            if (!g) return
            if (mode === "copy") onCopy(g)
            else onEditOrig(g)
            onOpenChange(false)
          }} />
        </div>
      </DialogContent>
    </Dialog>
  )
}
