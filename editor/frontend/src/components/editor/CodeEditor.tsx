import { useMemo, useRef, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ArrowDownIcon, ArrowUpIcon, PencilIcon, PlusIcon, Trash2Icon } from "lucide-react"
import { DETAIL, InstrLine, actorName, useOpsAndNames } from "./EventViewer"
import { OP_LABEL, OPERAND_LABEL } from "@/lib/opnames"
import type { Instr, MapInfo, Opcode, Override, Project } from "@/lib/types"

/** 指令的参数类型 (对白 text = 角色 + 9 个窗口参数 + 文本) */
function operandTypes(op: string, ops: Record<string, Opcode> | null): string {
  return ops?.[op]?.operands ?? ""
}

/** 新指令的默认参数: 数值 0, 文本空, 跳转 = 下一条, 列表空 */
function defaultArgs(types: string, next: number): Instr {
  return [...types].map((t) => (t === "T" ? "" : t === "r" ? next : "FRP".includes(t) ? [] : 0))
}

/** 本方案能引用的东西 (显示 / 选择用): "@npc:1" → 名字 */
export function modRefs(p: Project): Record<string, string> {
  const out: Record<string, string> = {}
  p.npcs.forEach((n) => (out[`@npc:${n.local}`] = `${n.name}（本方案）`))
  p.flags.forEach((f) => (out[`@flag:${f.local}`] = `F${f.local} ${f.name}（本方案）`))
  p.items.forEach((i) => (out[`@item:${i.local}`] = `${i.name}（本方案）`))
  p.events.forEach((e) => (out[`@event:${e.local}`] = `事件「${e.name}」（本方案）`))
  p.battles.forEach((b) => (out[`@battle:${b.local}`] = `${b.name}（本方案）`))
  p.models.forEach((m) => (out[`@model:${m.local}`] = `${m.name}（本方案）`))
  return out
}

const REF_KIND: Record<string, string> = { a: "npc", f: "flag", i: "item", e: "event", b: "battle" }

/** 一个参数的输入框: 数值 / 文本 / 跳转目标 / 原版编号或本方案引用 */
function ArgInput({ t, v, onChange, code, refs, maps }: {
  t: string; v: unknown; onChange: (v: string | number | (string | number)[]) => void
  code: Instr[]; refs: Record<string, string>; maps: MapInfo[] | null
}) {
  if (t === "T") {
    return <Textarea rows={3} value={String(v ?? "")} onChange={(e) => onChange(e.target.value)} className="font-sans"
      placeholder="%N 换行，%C5 颜色，%S3 字速（和原版写法一样）" />
  }
  if (t === "r") {
    return (
      <Select value={String(v)} onValueChange={(x) => onChange(Number(x))}>
        <SelectTrigger size="sm" className="w-72"><SelectValue /></SelectTrigger>
        <SelectContent className="max-h-72">
          {code.map((ins) => <SelectItem key={String(ins[0])} value={String(ins[0])}>@{String(ins[0])} {OP_LABEL[String(ins[1])] ?? String(ins[1])}</SelectItem>)}
        </SelectContent>
      </Select>
    )
  }
  if (t === "m") {
    return (
      <Select value={String(v)} onValueChange={(x) => onChange(Number(x))}>
        <SelectTrigger size="sm" className="w-56"><SelectValue placeholder="选择地图" /></SelectTrigger>
        <SelectContent className="max-h-72">
          {(maps ?? []).map((m) => <SelectItem key={m.id} value={String(m.id)}>{m.title || m.name} · {m.id}</SelectItem>)}
        </SelectContent>
      </Select>
    )
  }
  if ("FRP".includes(t)) {
    return <Input className="h-8 w-72" value={(v as unknown[] ?? []).join(", ")}
      onChange={(e) => onChange(e.target.value.split(/[,，\s]+/).filter(Boolean).map((x) => (/^-?\d+$/.test(x) ? Number(x) : x)))} />
  }
  const kind = REF_KIND[t]
  const mine = kind ? Object.entries(refs).filter(([k]) => k.startsWith(`@${kind}:`)) : []
  return (
    <div className="flex items-center gap-1.5">
      <Input className="h-8 w-28" value={String(v ?? 0)}
        onChange={(e) => onChange(/^-?\d+$/.test(e.target.value) ? Number(e.target.value) : e.target.value)} />
      {mine.length > 0 && (
        <Select value={typeof v === "string" ? v : ""} onValueChange={(x) => onChange(x)}>
          <SelectTrigger size="sm" className="w-44"><SelectValue placeholder="或选本方案的…" /></SelectTrigger>
          <SelectContent>{mine.map(([k, name]) => <SelectItem key={k} value={k}>{name}</SelectItem>)}</SelectContent>
        </Select>
      )}
    </div>
  )
}

/** 插入指令: 从原版全部指令里选 (中文名 / 助记符 / 说明都能搜, 常用的在前) */
function OpPicker({ ops, onPick }: { ops: Record<string, Opcode> | null; onPick: (op: string) => void }) {
  const [open, setOpen] = useState(false)
  const list = useMemo(() => Object.values(ops ?? {}).filter((o) => o.count > 0).sort((a, b) => b.count - a.count), [ops])
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon-xs" aria-label="在下面插入指令"><PlusIcon /></Button>
      </PopoverTrigger>
      <PopoverContent className="w-96 p-0" align="start">
        <Command filter={(value, search) => (value.toLowerCase().includes(search.toLowerCase()) ? 1 : 0)}>
          <CommandInput placeholder="搜指令：对白、旗标、镜头、give_item…" />
          <CommandList className="max-h-80">
            <CommandEmpty>没有这个指令</CommandEmpty>
            <CommandGroup heading="原版指令（按原版用得多少排序）">
              {list.map((o) => (
                <CommandItem key={o.name} value={`${OP_LABEL[o.name] ?? ""} ${o.name} ${o.note}`} onSelect={() => { onPick(o.name); setOpen(false) }}>
                  <div className="min-w-0">
                    <div>{OP_LABEL[o.name] ?? o.name} <span className="font-mono text-xs text-muted-foreground">{o.name}</span></div>
                    <div className="line-clamp-2 text-xs text-muted-foreground">{o.note}</div>
                  </div>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  )
}

/** 方案里的原版事件: 逐条指令编辑 (位置只是标签; 删掉被跳转的指令时, 跳过来的改成跳到下一条) */
export function CodeEditor({ ov, p, maps, onChange, action }: { ov: Override; p: Project; maps: MapInfo[] | null; onChange: (o: Override) => void; action?: React.ReactNode }) {
  const [ops, names] = useOpsAndNames()
  const [brief, setBrief] = useState(true)
  const [sel, setSel] = useState<number | null>(null) // 选中的位置
  const box = useRef<HTMLDivElement>(null)
  const refs = useMemo(() => modRefs(p), [p])
  const mapNames = useMemo(() => new Map((maps ?? []).map((m) => [m.id, m.title || m.name])), [maps])
  const code = ov.code
  const set = (c: Instr[]) => onChange({ ...ov, code: c })
  const idx = (pos: number) => code.findIndex((ins) => Number(ins[0]) === pos)
  const nextPos = () => code.reduce((m, ins) => Math.max(m, Number(ins[0])), 0) + 2

  // 改跳转: 指向 from 的都改成 to (操作数 r 和跳转表里的)
  const retarget = (c: Instr[], from: number, to: number): Instr[] =>
    c.map((ins) => {
      const types = operandTypes(String(ins[1]), ops)
      return ins.map((a, k) => {
        const t = k >= 2 ? types[k - 2] : ""
        if (t === "r" && Number(a) === from) return to
        if ((t === "R" || t === "P") && Array.isArray(a)) return a.map((x) => (Number(x) === from ? to : x))
        return a
      })
    })

  const del = (pos: number) => {
    const i = idx(pos)
    const after = code[i + 1] ? Number(code[i + 1][0]) : null
    let c = code.filter((_, k) => k !== i)
    if (after !== null) c = retarget(c, pos, after)
    set(c)
    setSel(after)
  }
  const move = (pos: number, d: number) => {
    const i = idx(pos), j = i + d
    if (j < 0 || j >= code.length) return
    const c = [...code]
    ;[c[i], c[j]] = [c[j], c[i]]
    set(c)
  }
  const insert = (pos: number, op: string) => {
    const i = idx(pos)
    const np = nextPos()
    const next = code[i + 1] ? Number(code[i + 1][0]) : np
    const ins: Instr = [np, op, ...defaultArgs(operandTypes(op, ops), next)]
    const c = [...code.slice(0, i + 1), ins, ...code.slice(i + 1)]
    set(c)
    setSel(np)
    setBrief(false)
  }
  const setArg = (pos: number, k: number, v: string | number | (string | number)[]) =>
    set(code.map((ins) => (Number(ins[0]) === pos ? ins.map((a, j) => (j === k ? v : a)) : ins)))
  const jump = (pos: number) => {
    setBrief(false)
    setSel(pos)
    setTimeout(() => box.current?.querySelector(`[data-pos="${pos}"]`)?.scrollIntoView({ block: "center", behavior: "smooth" }), 50)
  }
  const shown = brief ? code.filter((ins) => !DETAIL.has(String(ins[1])) || Number(ins[0]) === sel) : code
  return (
    <div className="flex h-full flex-col">
      <div className="flex flex-wrap items-center gap-2 border-b px-3 py-2 text-sm">
        <PencilIcon className="size-3.5 text-primary" />
        <span className="font-semibold">改原版事件 #{ov.id}</span>
        {ov.name && <Badge variant="secondary">{ov.name}</Badge>}
        <span className="text-xs text-muted-foreground">{code.length} 条指令 · 点一条展开编辑，＋ 在它下面插入</span>
        <div className="flex-1" />
        <label className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Switch size="sm" checked={brief} onCheckedChange={setBrief} />只看剧情
        </label>
        {action}
      </div>
      <ScrollArea className="min-h-0 flex-1">
        <div ref={box} className="font-mono text-[12.5px] leading-6">
          {shown.map((ins) => {
            const pos = Number(ins[0])
            const op = String(ins[1])
            const types = operandTypes(op, ops)
            const open = sel === pos
            return (
              <div key={pos} data-pos={pos} className={`group border-l-2 ${open ? "border-primary bg-primary/10" : "border-transparent hover:bg-accent/30"}`}>
                <div className="flex cursor-pointer gap-3 px-3" onClick={() => setSel(open ? null : pos)}>
                  <InstrLine ins={ins} ops={ops} names={names} maps={mapNames} onJump={jump} extra={refs} />
                  <span className={`flex shrink-0 items-center ${open ? "" : "opacity-0 group-hover:opacity-100"}`} onClick={(e) => e.stopPropagation()}>
                    <Button variant="ghost" size="icon-xs" aria-label="上移" onClick={() => move(pos, -1)}><ArrowUpIcon /></Button>
                    <Button variant="ghost" size="icon-xs" aria-label="下移" onClick={() => move(pos, 1)}><ArrowDownIcon /></Button>
                    <OpPicker ops={ops} onPick={(o) => insert(pos, o)} />
                    <Button variant="ghost" size="icon-xs" aria-label="删除" className="text-destructive" onClick={() => del(pos)}><Trash2Icon /></Button>
                  </span>
                </div>
                {open && (
                  <div className="space-y-2 px-3 pt-1 pb-3 pl-[4.25rem] font-sans">
                    <p className="text-xs text-muted-foreground">{ops?.[op]?.note}</p>
                    {[...types].map((t, k) => {
                      // 对白的 9 个窗口参数 (位置 / 大小 / 样式) 原样保留, 不在表单里显示
                      if (op === "text" && k >= 1 && k <= 9) return null
                      return (
                        <div key={k} className="flex items-start gap-2 text-sm">
                          <span className="w-14 shrink-0 pt-1.5 text-muted-foreground">{OPERAND_LABEL[t] ?? t}</span>
                          <div className="min-w-0 flex-1">
                            <ArgInput t={t} v={ins[k + 2]} code={code} refs={refs} maps={maps} onChange={(v) => setArg(pos, k + 2, v)} />
                            {t === "a" && typeof ins[k + 2] === "number" && <span className="text-xs text-muted-foreground">{actorName(Number(ins[k + 2]), names)}</span>}
                          </div>
                        </div>
                      )
                    })}
                    {types.length === 0 && <p className="text-xs text-muted-foreground">这条指令没有参数。</p>}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </ScrollArea>
    </div>
  )
}
