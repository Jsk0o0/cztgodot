import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu"
import { Empty, EmptyDescription, EmptyHeader, EmptyTitle } from "@/components/ui/empty"
import { ScrollArea } from "@/components/ui/scroll-area"
import { ArrowDownIcon, ArrowUpIcon, CoinsIcon, FlagIcon, GitBranchIcon, MessageSquareIcon, MoreHorizontalIcon, PackageIcon, PlusIcon, SquareIcon, Trash2Icon, BellIcon, StoreIcon, XIcon, ScrollTextIcon, PackageCheckIcon, SwordsIcon, HashIcon, UsersIcon } from "lucide-react"
import { ItemPicker, describeRef, useGameItems } from "./ItemPicker"
import { api } from "@/lib/api"
import { useOpsAndNames } from "./EventViewer"
import type { Names, Block, BlockType, GameEvent, Project } from "@/lib/types"

const META: Record<BlockType, { label: string; color: string; icon: React.ReactNode }> = {
  say: { label: "对话", color: "border-l-emerald-500/80 bg-emerald-500/5", icon: <MessageSquareIcon /> },
  notice: { label: "提示", color: "border-l-stone-400/80 bg-stone-400/5", icon: <BellIcon /> },
  money: { label: "金钱", color: "border-l-amber-500/80 bg-amber-500/5", icon: <CoinsIcon /> },
  item: { label: "道具", color: "border-l-orange-400/80 bg-orange-400/5", icon: <PackageIcon /> },
  shop: { label: "商店", color: "border-l-teal-500/80 bg-teal-500/5", icon: <StoreIcon /> },
  flag: { label: "旗标", color: "border-l-sky-500/80 bg-sky-500/5", icon: <FlagIcon /> },
  quest: { label: "任务", color: "border-l-rose-400/80 bg-rose-400/5", icon: <ScrollTextIcon /> },
  if_flag: { label: "如果旗标", color: "border-l-violet-500/80 bg-violet-500/5", icon: <GitBranchIcon /> },
  if_quest: { label: "如果任务", color: "border-l-violet-500/80 bg-violet-500/5", icon: <GitBranchIcon /> },
  if_item: { label: "如果有物品", color: "border-l-violet-500/80 bg-violet-500/5", icon: <PackageCheckIcon /> },
  var: { label: "变量", color: "border-l-cyan-500/80 bg-cyan-500/5", icon: <HashIcon /> },
  if_var: { label: "如果变量", color: "border-l-violet-500/80 bg-violet-500/5", icon: <GitBranchIcon /> },
  party: { label: "入队 / 离队", color: "border-l-indigo-400/80 bg-indigo-400/5", icon: <UsersIcon /> },
  battle: { label: "开战", color: "border-l-red-500/80 bg-red-500/5", icon: <SwordsIcon /> },
  end: { label: "结束", color: "border-l-stone-500/80 bg-stone-500/5", icon: <SquareIcon /> },
}

function fresh(type: BlockType, p: Project): Block {
  const f = p.flags[0]?.local ?? 0
  switch (type) {
    case "say":
      return { type, speaker: p.npcs[0] ? `npc:${p.npcs[0].local}` : "player", text: "" }
    case "notice":
      return { type, text: "" }
    case "money":
      return { type, amount: 100 }
    case "item":
      return p.items[0] ? { type, modItem: p.items[0].local, count: 1 } : { type, item: 3001, count: 1 }
    case "shop":
      return { type, goods: [...p.items.map((m) => ({ modItem: m.local })), { item: 3001 }] }
    case "flag":
      return { type, flag: f, on: true }
    case "if_flag":
      return { type, flag: f, then: [], else: [] }
    case "quest":
      return { type, quest: p.quests[0]?.local ?? 0, step: "accept" }
    case "if_quest":
      return { type, quest: p.quests[0]?.local ?? 0, state: "active", then: [], else: [] }
    case "if_item":
      return { type, item: 3001, count: 1, then: [], else: [] }
    case "battle":
      return { type, battle: p.battles[0]?.local ?? 0 }
    case "party":
      return { type, member: 2, on: true }
    case "var":
      return { type, var: p.vars[0]?.local ?? 0, op: "add", value: 1 }
    case "if_var":
      return { type, var: p.vars[0]?.local ?? 0, cmp: "ge", value: 1, then: [], else: [] }
    default:
      return { type }
  }
}

// 道具名: 查到后写进积木 (itemName), 提示框「得到【名字】」要用
function ItemName({ b, onChange }: { b: Block; onChange: (b: Block) => void }) {
  const [name, setName] = useState(b.itemName ?? "")
  useEffect(() => {
    let alive = true
    api.itemName(b.item ?? 0).then((n) => {
      if (!alive) return
      setName(n)
      if (n !== (b.itemName ?? "")) onChange({ ...b, itemName: n })
    })
    return () => {
      alive = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [b.item])
  return <span className="text-xs text-muted-foreground">{name || "（没有这个道具）"}</span>
}

// 商店积木: 卖哪些东西 (价格用物品自己的; 原版商店同样只给物品清单)
function ShopGoods({ b, p, onChange }: { b: Block; p: Project; onChange: (b: Block) => void }) {
  const game = useGameItems()
  const goods = b.goods ?? []
  const set = (g: typeof goods) => onChange({ ...b, goods: g })
  return (
    <div className="flex w-full flex-col gap-1.5">
      <span className="text-muted-foreground">开一家店，卖：</span>
      {goods.map((g, i) => (
        <div key={i} className="flex items-center gap-2">
          <ItemPicker p={p} value={g} className="w-52" onChange={(r) => set(goods.map((x, k) => (k === i ? r : x)))} />
          <span className="text-xs text-muted-foreground">{describeRef(g, p, game).price ?? "—"} 文</span>
          <Button variant="ghost" size="icon-sm" aria-label="不卖这件" onClick={() => set(goods.filter((_, k) => k !== i))}><XIcon /></Button>
        </div>
      ))}
      <Button variant="outline" size="sm" className="w-fit" onClick={() => set([...goods, { item: 3001 }])}><PlusIcon />加一件货</Button>
    </div>
  )
}

function NoticeSwitch({ b, onChange }: { b: Block; onChange: (b: Block) => void }) {
  return (
    <label className="flex items-center gap-1.5 text-xs text-muted-foreground">
      <Switch size="sm" checked={!b.quiet} onCheckedChange={(v) => onChange({ ...b, quiet: !v })} />弹出提示
    </label>
  )
}

/** 游戏里会显示的文字 (金钱 / 道具自动弹的提示同 Go 端 compile.go) */
export function previewOf(b: Block, p: Project, names?: Names | null): { speaker?: string; text: string; center?: boolean } | null {
  switch (b.type) {
    case "say": {
      const n = b.speaker?.startsWith("npc:") ? p.npcs.find((x) => `npc:${x.local}` === b.speaker) : null
      const orig = b.speaker?.startsWith("actor:") ? Number(b.speaker.slice(6)) : 0
      const on = orig ? p.npcEdits.find((e) => e.actor === orig)?.name ?? names?.people[String(orig)] : undefined
      return { speaker: b.speaker === "player" || !b.speaker ? "车芸" : n?.name || on || "（NPC）", text: b.text || "" }
    }
    case "notice":
      return { text: b.text || "", center: true }
    case "money":
      if (b.quiet || !b.amount) return null
      return { text: `${b.amount > 0 ? "得到" : "失去"}【${Math.abs(b.amount)} 金】`, center: true }
    case "item": {
      if (b.quiet || !b.count) return null
      const nm = b.modItem ? p.items.find((m) => m.local === b.modItem)?.name ?? `物品 #${b.modItem}` : b.itemName || `道具 ${b.item}`
      return { text: `${b.count > 0 ? "得到" : "失去"}【${nm}】${Math.abs(b.count) > 1 ? ` ×${Math.abs(b.count)}` : ""}`, center: true }
    }
    case "shop":
      return { text: "客倌 您要买东西还是卖东西\n买　　卖　　离开", center: true }
    case "quest":
      return b.quiet ? null : { text: "任务更新", center: true }
  }
  return null
}

function BlockRow({ b, p, onChange, onDelete, onMove, first, last, path, active, onFocus }: {
  b: Block; p: Project; onChange: (b: Block) => void; onDelete: () => void; onMove: (d: number) => void; first: boolean; last: boolean
  path: string; active: string; onFocus: (path: string) => void
}) {
  const [, names] = useOpsAndNames()
  const m = META[b.type]
  const questSelect = (
    <Select value={String(b.quest ?? 0)} onValueChange={(v) => onChange({ ...b, quest: Number(v) })}>
      <SelectTrigger size="sm" className="w-48"><SelectValue placeholder="选择任务" /></SelectTrigger>
      <SelectContent>
        {p.quests.length === 0 && <SelectItem value="0" disabled>还没有任务（左边「任务」+ 新建）</SelectItem>}
        {p.quests.map((q) => <SelectItem key={q.local} value={String(q.local)}>{q.main ? "★" : "☆"}{q.title}</SelectItem>)}
      </SelectContent>
    </Select>
  )
  const flagSelect = (
    <Select value={String(b.flag ?? 0)} onValueChange={(v) => onChange({ ...b, flag: Number(v) })}>
      <SelectTrigger size="sm" className="w-40"><SelectValue placeholder="选择旗标" /></SelectTrigger>
      <SelectContent>
        {p.flags.length === 0 && <SelectItem value="0" disabled>还没有旗标</SelectItem>}
        {p.flags.map((f) => <SelectItem key={f.local} value={String(f.local)}>F{f.local} {f.name}</SelectItem>)}
      </SelectContent>
    </Select>
  )
  const varSelect = (
    <Select value={String(b.var ?? 0)} onValueChange={(v) => onChange({ ...b, var: Number(v) })}>
      <SelectTrigger size="sm" className="w-40"><SelectValue placeholder="选择变量" /></SelectTrigger>
      <SelectContent>
        {p.vars.length === 0 && <SelectItem value="0" disabled>还没有变量（左边「变量」+ 新建）</SelectItem>}
        {p.vars.map((x) => <SelectItem key={x.local} value={String(x.local)}>{x.name}</SelectItem>)}
      </SelectContent>
    </Select>
  )
  const valueInput = (
    <Input type="number" min={0} max={65535} value={b.value ?? 0} className="h-8 w-20"
      onChange={(e) => onChange({ ...b, value: Math.min(65535, Math.max(0, Math.round(Number(e.target.value) || 0))) })} />
  )
  return (
    <div data-block-path={path} className={`rounded-md border border-l-4 ${m.color} p-2 ${active === path ? "ring-1 ring-primary/60" : ""}`}>
      <div className="flex items-start gap-2">
        <Badge variant="secondary" className="mt-1 shrink-0 gap-1">{m.icon}{m.label}</Badge>
        <div className="flex min-w-0 flex-1 flex-wrap items-center gap-2 text-sm">
          {b.type === "say" && (
            <>
              <Select value={b.speaker} onValueChange={(v) => onChange({ ...b, speaker: v })}>
                <SelectTrigger size="sm" className="w-40"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="player">车芸（主角）</SelectItem>
                  {p.npcs.map((n) => <SelectItem key={n.local} value={`npc:${n.local}`}>{n.name || `NPC ${n.local}`}</SelectItem>)}
                  {/* 原版角色: 队友、方案改过的原版 NPC、积木里已经写了的 */}
                  {[...new Set([2, 3, ...p.npcEdits.map((e) => e.actor), ...(b.speaker?.startsWith("actor:") ? [Number(b.speaker.slice(6))] : [])])].map((a) => (
                    <SelectItem key={`a${a}`} value={`actor:${a}`}>{p.npcEdits.find((e) => e.actor === a)?.name ?? (names?.people[String(a)] || `原版角色 ${a}`)}（原版）</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Textarea value={b.text} rows={2} placeholder="说的话（回车换行）" className="min-h-0 w-full resize-none"
                onChange={(e) => onChange({ ...b, text: e.target.value })} />
            </>
          )}
          {b.type === "notice" && (
            <Input value={b.text} placeholder="提示内容，例如：得到 9999 金" className="h-8 flex-1" onChange={(e) => onChange({ ...b, text: e.target.value })} />
          )}
          {b.type === "money" && (
            <>增加 <Input type="number" value={b.amount} className="h-8 w-28" onChange={(e) => onChange({ ...b, amount: Number(e.target.value) })} /> 金
              <NoticeSwitch b={b} onChange={onChange} /></>
          )}
          {b.type === "item" && (
            <><ItemPicker p={p} value={{ item: b.item, modItem: b.modItem }} className="w-48"
                onChange={(r) => onChange({ ...b, item: r.item, modItem: r.modItem, itemName: undefined })} />
              数量 <Input type="number" value={b.count} className="h-8 w-20" onChange={(e) => onChange({ ...b, count: Number(e.target.value) })} />
              {!b.modItem && <ItemName b={b} onChange={onChange} />}<NoticeSwitch b={b} onChange={onChange} /></>
          )}
          {b.type === "shop" && <ShopGoods b={b} p={p} onChange={onChange} />}
          {b.type === "flag" && (
            <>{flagSelect}<Switch checked={b.on} onCheckedChange={(v) => onChange({ ...b, on: v })} />{b.on ? "设置" : "清除"}</>
          )}
          {b.type === "if_flag" && <>旗标 {flagSelect} 已设置时</>}
          {b.type === "party" && (
            <><Select value={String(b.member ?? 2)} onValueChange={(v) => onChange({ ...b, member: Number(v) })}>
                <SelectTrigger size="sm" className="w-28"><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="2">嬴诗</SelectItem><SelectItem value="3">桓远之</SelectItem></SelectContent>
              </Select>
              <Select value={b.on ? "in" : "out"} onValueChange={(v) => onChange({ ...b, on: v === "in" })}>
                <SelectTrigger size="sm" className="w-24"><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="in">入队</SelectItem><SelectItem value="out">离队</SelectItem></SelectContent>
              </Select></>
          )}
          {b.type === "var" && (
            <>{varSelect}
              <Select value={b.op ?? "add"} onValueChange={(v) => onChange({ ...b, op: v as Block["op"] })}>
                <SelectTrigger size="sm" className="w-24"><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="add">加上</SelectItem><SelectItem value="set">设成</SelectItem></SelectContent>
              </Select>{valueInput}</>
          )}
          {b.type === "if_var" && (
            <>{varSelect}
              <Select value={b.cmp ?? "ge"} onValueChange={(v) => onChange({ ...b, cmp: v as Block["cmp"] })}>
                <SelectTrigger size="sm" className="w-24"><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="ge">≥</SelectItem><SelectItem value="eq">=</SelectItem></SelectContent>
              </Select>{valueInput}</>
          )}
          {b.type === "quest" && (
            <>{questSelect}
              <Select value={b.step ?? "accept"} onValueChange={(v) => onChange({ ...b, step: v as Block["step"] })}>
                <SelectTrigger size="sm" className="w-28"><SelectValue /></SelectTrigger>
                <SelectContent><SelectItem value="accept">接受任务</SelectItem><SelectItem value="done">完成任务</SelectItem></SelectContent>
              </Select>
              <NoticeSwitch b={b} onChange={onChange} /></>
          )}
          {b.type === "if_quest" && (
            <>{questSelect}
              <Select value={b.state ?? "active"} onValueChange={(v) => onChange({ ...b, state: v as Block["state"] })}>
                <SelectTrigger size="sm" className="w-28"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">还没接</SelectItem><SelectItem value="active">进行中</SelectItem><SelectItem value="done">已完成</SelectItem>
                </SelectContent>
              </Select></>
          )}
          {b.type === "if_item" && (
            <>身上有 <ItemPicker p={p} value={{ item: b.item, modItem: b.modItem }} className="w-36"
                onChange={(r) => onChange({ ...b, item: r.item, modItem: r.modItem })} />
              至少 <Input type="number" min={1} value={b.count} className="h-8 w-16" onChange={(e) => onChange({ ...b, count: Math.max(1, Number(e.target.value)) })} /> 个</>
          )}
          {b.type === "battle" && (
            <><Select value={String(b.battle ?? 0)} onValueChange={(v) => onChange({ ...b, battle: Number(v) })}>
                <SelectTrigger size="sm" className="w-48"><SelectValue placeholder="选择战斗" /></SelectTrigger>
                <SelectContent>
                  {p.battles.length === 0 && <SelectItem value="0" disabled>还没有战斗（左边「战斗」+ 新建）</SelectItem>}
                  {p.battles.map((x) => <SelectItem key={x.local} value={String(x.local)}>{x.name}</SelectItem>)}
                </SelectContent>
              </Select>
              <span className="text-xs text-muted-foreground">打赢后接着往下；输了回标题（同原版剧情战）</span></>
          )}
          {b.type === "end" && <span className="text-muted-foreground">在这里结束事件</span>}
        </div>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon-sm" aria-label="积木操作"><MoreHorizontalIcon /></Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem disabled={first} onSelect={() => onMove(-1)}><ArrowUpIcon />上移</DropdownMenuItem>
            <DropdownMenuItem disabled={last} onSelect={() => onMove(1)}><ArrowDownIcon />下移</DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem variant="destructive" onSelect={onDelete}><Trash2Icon />删除</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      {(b.type === "if_flag" || b.type === "if_quest" || b.type === "if_item" || b.type === "if_var") && (
        <div className="mt-2 space-y-2 pl-4">
          <div className="text-xs text-muted-foreground">{b.type === "if_flag" ? "已设置时" : b.type === "if_item" ? "有的话" : "是的话"}</div>
          <BlockList blocks={b.then ?? []} p={p} onChange={(then) => onChange({ ...b, then })} nested path={`${path}.then`} active={active} onFocus={onFocus} />
          <div className="text-xs text-muted-foreground">否则</div>
          <BlockList blocks={b.else ?? []} p={p} onChange={(els) => onChange({ ...b, else: els })} nested path={`${path}.else`} active={active} onFocus={onFocus} />
        </div>
      )}
    </div>
  )
}

function BlockList({ blocks, p, onChange, path, active, onFocus }: {
  blocks: Block[]; p: Project; onChange: (b: Block[]) => void; nested?: boolean; path: string; active: string; onFocus: (path: string) => void
}) {
  const set = (i: number, b: Block) => onChange(blocks.map((x, k) => (k === i ? b : x)))
  const move = (i: number, d: number) => {
    const a = [...blocks]
    ;[a[i], a[i + d]] = [a[i + d], a[i]]
    onChange(a)
  }
  return (
    <div className="space-y-2">
      {blocks.map((b, i) => (
        <BlockRow key={i} b={b} p={p} first={i === 0} last={i === blocks.length - 1} path={`${path}.${i}`} active={active} onFocus={onFocus}
          onChange={(nb) => set(i, nb)} onDelete={() => onChange(blocks.filter((_, k) => k !== i))} onMove={(d) => move(i, d)} />
      ))}
      <div className="flex flex-wrap gap-1.5">
        {/* 条件可以嵌套 (例 任务进行中 → 身上有 3 株草药 → 交任务) */}
        {(Object.keys(META) as BlockType[]).map((t) => (
          <Button key={t} variant="outline" size="xs" onClick={() => onChange([...blocks, fresh(t, p)])}>
            <PlusIcon />{META[t].label}
          </Button>
        ))}
      </div>
    </div>
  )
}

// 按路径 ("b.0.then.1") 取积木
function blockAt(blocks: Block[], path: string): Block | null {
  const parts = path.split(".").slice(1)
  let list: Block[] | undefined = blocks
  let cur: Block | null = null
  for (let i = 0; i < parts.length; i++) {
    const k = parts[i]
    if (k === "then" || k === "else") {
      list = cur?.[k]
      continue
    }
    cur = list?.[Number(k)] ?? null
    if (!cur) return null
  }
  return cur
}

// 第一个能预览的积木
function firstPreview(blocks: Block[], p: Project, path = "b"): string {
  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i]
    if (previewOf(b, p)) return `${path}.${i}`
    for (const br of ["else", "then"] as const) {
      const r = firstPreview(b[br] ?? [], p, `${path}.${i}.${br}`)
      if (r) return r
    }
  }
  return ""
}

function DialogPreview({ block, p }: { block: Block | null; p: Project }) {
  const [, names] = useOpsAndNames()
  const pv = block ? previewOf(block, p, names) : null
  return (
    <div className="flex h-full flex-col gap-2 border-l p-3 text-xs text-muted-foreground">
      <div className="text-sm text-foreground">对话预览</div>
      <div className="relative flex-1 overflow-hidden rounded-md border bg-[linear-gradient(160deg,#5a4b3b,#2c241d)]">
        {pv ? (
          pv.center ? (
            <div className="absolute top-1/2 left-1/2 w-max max-w-[90%] -translate-x-1/2 -translate-y-1/2 rounded-md border-2 border-[#c99a62]/80 bg-black/60 px-4 py-2 text-center font-serif text-[15px] whitespace-pre-wrap text-white">
              {pv.text.split(/(【[^】]*】)/).map((s, i) => s.startsWith("【") ? <span key={i}>【<span className="text-[#ffa832]">{s.slice(1, -1)}</span>】</span> : <span key={i}>{s}</span>)}
            </div>
          ) : (
            <div className="absolute inset-x-3 bottom-3">
              <div className="mb-[-2px] ml-2 inline-block rounded-t-md border-2 border-b-0 border-[#c99a62]/80 bg-black/60 px-2 py-0.5 font-serif text-[13px] text-[#e7cfab]">{pv.speaker}</div>
              <div className="min-h-16 rounded-md border-2 border-[#c99a62]/80 bg-black/60 px-3 py-2 font-serif text-[15px] leading-relaxed whitespace-pre-wrap text-white">
                {pv.text || <span className="text-white/40">（还没写内容）</span>}
              </div>
            </div>
          )
        ) : (
          <div className="absolute inset-0 flex items-center justify-center p-4 text-center">
            {block && (block.type === "money" || block.type === "item")
              ? "这一块关掉了「弹出提示」，游戏里只会默默加上，不显示文字。"
              : block ? "这一块在游戏里没有文字。" : "点一下左边的对话、提示、金钱或道具积木，这里显示它在游戏里的样子。"}
          </div>
        )}
      </div>
      <p>大致样子：游戏里对话框按原版样式显示在说话人头上。</p>
    </div>
  )
}

export function EventEditor({ project, event, onChange }: { project: Project; event: GameEvent | null; onChange: (e: GameEvent) => void }) {
  const [, names] = useOpsAndNames()
  const [focus, setFocus] = useState("")
  if (!event) {
    return (
      <Empty className="h-full">
        <EmptyHeader>
          <EmptyTitle>没有选中事件</EmptyTitle>
          <EmptyDescription>在左边「事件」里选一个，或新建事件后在这里用积木编写对话和奖励。</EmptyDescription>
        </EmptyHeader>
      </Empty>
    )
  }
  const path = focus && blockAt(event.blocks, focus) ? focus : firstPreview(event.blocks, project)
  return (
    <div className="grid h-full grid-cols-[1fr_300px]">
    <ScrollArea className="h-full min-w-0">
      {/* 点到 / 焦点进入哪块积木 (最近的 data-block-path), 预览就显示哪块 */}
      <div className="space-y-3 p-3"
        onPointerDownCapture={(e) => { const el = (e.target as HTMLElement).closest("[data-block-path]"); if (el) setFocus(el.getAttribute("data-block-path")!) }}
        onFocusCapture={(e) => { const el = (e.target as HTMLElement).closest("[data-block-path]"); if (el) setFocus(el.getAttribute("data-block-path")!) }}>
        <div className="flex items-center gap-2">
          <span className="text-sm text-muted-foreground">事件 #{event.local}</span>
          <Input value={event.name} className="h-8 w-56" onChange={(e) => onChange({ ...event, name: e.target.value })} />
          <span className="text-xs text-muted-foreground">
            触发：{[...project.npcs.filter((n) => n.event === event.local).map((n) => `和「${n.name}」对话`),
              ...project.npcEdits.filter((e) => e.modEvent === event.local).map((e) => `和原版「${e.name ?? (names?.people[String(e.actor)] || e.actor)}」对话`)].join("、") || "还没有 NPC 用它"}
          </span>
        </div>
        <BlockList blocks={event.blocks} p={project} onChange={(blocks) => onChange({ ...event, blocks })} path="b" active={path} onFocus={setFocus} />
      </div>
    </ScrollArea>
    <DialogPreview block={path ? blockAt(event.blocks, path) : null} p={project} />
    </div>
  )
}
