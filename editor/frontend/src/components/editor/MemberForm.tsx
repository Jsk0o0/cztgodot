import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Checkbox } from "@/components/ui/checkbox"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Skeleton } from "@/components/ui/skeleton"
import { PlusIcon, RotateCcwIcon, SwordIcon, UsersIcon, XIcon } from "lucide-react"
import { api } from "@/lib/api"
import { ItemPicker } from "./ItemPicker"
import { MEMBER_NAMES, SkillPicker } from "./SkillForm"
import type { CharEdit, GameMember, GameNewGame, GrowthRow, Model, NewGameEdit, Project, SkillRef } from "@/lib/types"

let cache: Promise<{ members: GameMember[]; newGame: GameNewGame }> | null = null
export function useGameMembers() {
  const [v, setV] = useState<{ members: GameMember[]; newGame: GameNewGame } | null>(null)
  useEffect(() => {
    let alive = true
    cache ??= api.getMembers().catch((e) => { cache = null; throw e })
    cache.then((x) => alive && setV(x)).catch(() => {})
    return () => { alive = false }
  }, [])
  return v
}

const STATS: [string, string][] = [["level", "初始等级"], ["hp", "生命"], ["mp", "灵力"], ["sp", "体力"], ["atk", "攻击"], ["def", "防御"], ["spd", "速度"],
  ["matk", "仙攻"], ["mdef", "仙防"], ["hit", "命中"], ["eva", "闪避"], ["mhit", "仙术命中"], ["meva", "仙术闪避"], ["crit", "暴击"]]
// 成长表 12 列 (同游戏 State.add_exp 的顺序)
const GROWTH_COLS = ["生命", "灵力", "体力", "攻", "防", "仙攻", "仙防", "命中", "闪避", "仙命", "仙避", "速度"]

function toRows(g: number[][]): GrowthRow[] {
  return g.map((r) => ({ lv: r[0], inc: r.slice(1, 13), learn: r[13] ? { skill: r[13] } : {} }))
}

/** 改一名队员: 名字 / 说明 / 初始数值 / 成长表 (每级加多少、学会什么技能) / 车芸的地图模型 */
export function MemberForm({ id, p, models, onChange }: { id: number; p: Project; models: Model[] | null; onChange: (chars: CharEdit[]) => void }) {
  const data = useGameMembers()
  const orig = data?.members.find((m) => m.id === id)
  const ed: CharEdit = p.characters.find((c) => c.id === id) ?? { id }
  const others = p.characters.filter((c) => c.id !== id)
  const set = (patch: Partial<CharEdit>) => {
    const next = { ...ed, ...patch }
    const used = Object.keys(next).some((k) => k !== "id" && next[k as keyof CharEdit] !== undefined)
    onChange(used ? [...others, next].sort((a, b) => a.id - b.id) : others)
  }
  if (!orig) return <div className="space-y-2 p-4">{[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-8 w-full" />)}</div>
  const stat = (k: string) => ed.stats?.[k] ?? orig.stats[k] ?? 0
  const setStat = (k: string, v: number) => {
    const st = { ...(ed.stats ?? {}) }
    if (v === orig.stats[k]) delete st[k]
    else st[k] = v
    set({ stats: Object.keys(st).length ? st : undefined })
  }
  const rows = ed.growth ?? toRows(orig.growth)
  const setRow = (i: number, r: GrowthRow) => set({ growth: rows.map((x, k) => (k === i ? r : x)) })
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary"><UsersIcon className="size-4" />队员 · {MEMBER_NAMES[id]}</div>
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="mn">名字</FieldLabel>
          <Input id="mn" value={ed.name ?? orig.name} onChange={(e) => set({ name: e.target.value === orig.name ? undefined : e.target.value })} />
          <FieldDescription>菜单、战斗、对话框标题都用这个名字。原版剧情对白里写死的称呼不会变（要改就复制那段剧情到方案里改）。</FieldDescription>
        </Field>
        <Field>
          <FieldLabel htmlFor="md">说明</FieldLabel>
          <Textarea id="md" rows={2} value={ed.desc ?? orig.desc} onChange={(e) => set({ desc: e.target.value === orig.desc ? undefined : e.target.value })} />
        </Field>
        {id === 1 && (
          <Field>
            <FieldLabel>地图上的模型</FieldLabel>
            <Select value={ed.mapModel ? `m${ed.mapModel}` : String(ed.mapAct ?? orig.act)}
              onValueChange={(v) => v.startsWith("m") ? set({ mapModel: Number(v.slice(1)), mapAct: undefined })
                : set({ mapModel: undefined, mapAct: Number(v) === orig.act ? undefined : Number(v) })}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent className="max-h-80">
                {p.models.length > 0 && <SelectGroup><SelectLabel>本方案的模型</SelectLabel>
                  {p.models.map((m) => <SelectItem key={m.local} value={`m${m.local}`}>{m.name}</SelectItem>)}</SelectGroup>}
                <SelectGroup><SelectLabel>原版模型</SelectLabel>
                  {!models?.some((m) => m.act === orig.act) && <SelectItem value={String(orig.act)}>车芸（原版 {orig.act}）</SelectItem>}
                  {(models ?? []).map((m) => <SelectItem key={m.act} value={String(m.act)}>{m.label} · {m.act}{m.act === orig.act ? "（原版）" : ""}</SelectItem>)}
                </SelectGroup>
              </SelectContent>
            </Select>
            <FieldDescription>「换主角」：地图上一直是 1 号角色在走，原版剧情几千处指令都点名它，所以换的是它的样子和名字。新开游戏生效。</FieldDescription>
          </Field>
        )}
        <Field>
          <FieldLabel>初始数值</FieldLabel>
          <div className="grid grid-cols-2 gap-x-3 gap-y-2">
            {STATS.map(([k, label]) => (
              <label key={k} className="grid grid-cols-[4.5rem_1fr] items-center gap-2 text-sm">
                <span className={ed.stats?.[k] !== undefined ? "text-primary" : ""}>{label}</span>
                <Input type="number" min={k === "level" ? 1 : 0} max={k === "level" ? 99 : undefined} className="h-8" value={stat(k)} title={`原版 ${orig.stats[k]}`}
                  onChange={(e) => setStat(k, Math.max(0, Math.round(Number(e.target.value) || 0)))} />
              </label>
            ))}
          </div>
          <FieldDescription>新开游戏时队员是这个等级、这些数值（读档的照存档）。改过的项标橙色。</FieldDescription>
        </Field>
        <Field>
          <div className="flex items-center justify-between">
            <FieldLabel>成长表（升到这一级时加多少、学会什么技能）</FieldLabel>
            {ed.growth && <Button variant="ghost" size="sm" onClick={() => set({ growth: undefined })}><RotateCcwIcon />恢复原版</Button>}
          </div>
          <div className="max-h-96 overflow-auto rounded-md border">
            <table className="w-full text-xs">
              <thead className="sticky top-0 bg-card text-muted-foreground">
                <tr><th className="px-1 py-1">级</th>{GROWTH_COLS.map((c) => <th key={c} className="px-0.5 font-normal">{c}</th>)}<th className="px-1 text-left font-normal">学会</th></tr>
              </thead>
              <tbody>
                {rows.map((r, i) => i === 0 ? null : (
                  <tr key={r.lv} className={r.learn.skill || r.learn.modSkill ? "bg-primary/5" : ""}>
                    <td className="px-1 text-center text-muted-foreground">{r.lv}</td>
                    {r.inc.map((v, k) => (
                      <td key={k} className="p-0">
                        <input className="h-6 w-9 bg-transparent text-center outline-none focus:bg-accent" value={v}
                          onChange={(e) => { const inc = [...r.inc]; inc[k] = Math.round(Number(e.target.value) || 0); setRow(i, { ...r, inc }) }} />
                      </td>
                    ))}
                    <td className="py-0.5 pr-1"><SkillPicker p={p} value={r.learn} allowNone className="w-32" onChange={(learn) => setRow(i, { ...r, learn })} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <FieldDescription>同原版：经验够了升一级，加上这一行，生命 / 灵力 / 体力回满；有「学会」的这一级习得那个技能（可以选本方案的新技能）。</FieldDescription>
        </Field>
      </FieldGroup>
    </div>
  )
}

/** 改开局: 金钱 / 物品 / 开局在队的 / 各人开局会的技能 */
export function NewGameForm({ p, onChange }: { p: Project; onChange: (ng: NewGameEdit | null) => void }) {
  const data = useGameMembers()
  const ng = p.newGame ?? {}
  const set = (patch: Partial<NewGameEdit>) => {
    const next = { ...ng, ...patch }
    const used = Object.values(next).some((v) => v !== undefined)
    onChange(used ? next : null)
  }
  if (!data) return <div className="space-y-2 p-4">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-8 w-full" />)}</div>
  const o = data.newGame
  const items = ng.items ?? o.items.map((x) => ({ item: x }))
  const party = ng.party ?? [1]
  const skillsOf = (m: number): SkillRef[] => ng.skills?.[m] ?? (o.skills[String(m)] ?? []).map((x) => ({ skill: x }))
  const setSkills = (m: number, l: SkillRef[]) => set({ skills: { ...(ng.skills ?? {}), [m]: l } })
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary"><SwordIcon className="size-4" />开局（新游戏）</div>
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="ngm">金钱</FieldLabel>
          <Input id="ngm" type="number" min={0} value={ng.money ?? o.money} onChange={(e) => { const v = Math.max(0, Math.round(Number(e.target.value) || 0)); set({ money: v === o.money ? undefined : v }) }} />
          <FieldDescription>原版 {o.money}。</FieldDescription>
        </Field>
        <Field>
          <FieldLabel>开局在队</FieldLabel>
          <div className="flex gap-4 text-sm">
            <label className="flex items-center gap-1.5"><Checkbox checked disabled />车芸</label>
            {[2, 3].map((m) => (
              <label key={m} className="flex items-center gap-1.5">
                <Checkbox checked={party.includes(m)} onCheckedChange={(v) => {
                  const np = v ? [...new Set([...party, m])].sort() : party.filter((x) => x !== m)
                  set({ party: np.length > 1 ? np : undefined })
                }} />{MEMBER_NAMES[m]}
              </label>
            ))}
          </div>
          <FieldDescription>原版只有车芸，嬴诗、桓远之在剧情里入队（入队 / 离队 = 剧情里设 / 清旗标 2、3）。车芸一定在队。</FieldDescription>
        </Field>
        <Field>
          <FieldLabel>开局物品</FieldLabel>
          <div className="space-y-1.5">
            {items.map((it, i) => (
              <div key={i} className="flex items-center gap-2">
                <ItemPicker p={p} value={it} className="min-w-0 flex-1" onChange={(r) => set({ items: items.map((x, k) => (k === i ? r : x)) })} />
                <Button variant="ghost" size="icon-sm" aria-label="去掉" onClick={() => set({ items: items.filter((_, k) => k !== i) })}><XIcon /></Button>
              </div>
            ))}
            <Button variant="outline" size="sm" onClick={() => set({ items: [...items, { item: 3001 }] })}><PlusIcon />加一件</Button>
          </div>
        </Field>
        {[1, 2, 3].map((m) => (
          <Field key={m}>
            <FieldLabel>{MEMBER_NAMES[m]}开局会的技能</FieldLabel>
            <div className="flex flex-wrap gap-1.5">
              {skillsOf(m).map((r, i) => (
                <span key={i} className="flex items-center">
                  <SkillPicker p={p} value={r} className="w-28" onChange={(nr) => setSkills(m, skillsOf(m).map((x, k) => (k === i ? nr : x)))} />
                  <Button variant="ghost" size="icon-xs" aria-label="去掉" onClick={() => setSkills(m, skillsOf(m).filter((_, k) => k !== i))}><XIcon /></Button>
                </span>
              ))}
              <Button variant="outline" size="sm" className="h-7" onClick={() => setSkills(m, [...skillsOf(m), { skill: 6401 }])}><PlusIcon />加</Button>
            </div>
          </Field>
        ))}
        {p.newGame && <Button variant="outline" size="sm" onClick={() => onChange(null)}><RotateCcwIcon />开局全部恢复原版</Button>}
      </FieldGroup>
    </div>
  )
}
