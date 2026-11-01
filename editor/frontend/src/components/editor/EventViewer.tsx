import { useEffect, useMemo, useRef, useState } from "react"
import { Badge } from "@/components/ui/badge"
import { Switch } from "@/components/ui/switch"
import { Skeleton } from "@/components/ui/skeleton"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { Empty, EmptyDescription, EmptyHeader, EmptyTitle } from "@/components/ui/empty"
import { LockIcon } from "lucide-react"
import { api, errText } from "@/lib/api"
import { OP_LABEL } from "@/lib/opnames"
import type { EventInfo, MapInfo, Names, Opcode } from "@/lib/types"

// 指令表 / 名字表只读一次
let opsCache: Promise<Record<string, Opcode>> | null = null
let namesCache: Promise<Names> | null = null
export function useOpsAndNames(): [Record<string, Opcode> | null, Names | null] {
  const [ops, setOps] = useState<Record<string, Opcode> | null>(null)
  const [names, setNames] = useState<Names | null>(null)
  useEffect(() => {
    let alive = true
    opsCache ??= api.listOpcodes()
    namesCache ??= api.getNames()
    opsCache.then((v) => alive && setOps(v)).catch(() => { opsCache = null })
    namesCache.then((v) => alive && setNames(v)).catch(() => { namesCache = null })
    return () => {
      alive = false
    }
  }, [])
  return [ops, names]
}

// 只看剧情时隐藏的「排版 / 镜头细节」指令
export const DETAIL = new Set(["window_color", "text_char_spacing", "text_line_spacing", "wait_text", "set_caption", "reset_move_speed", "nop",
  "camera_angle_speed", "camera_distance_speed", "camera_target_speed", "camera_nowait", "camera_batch_begin", "camera_batch_end",
  "camera_zoom", "camera_wait", "wait_camera", "camera_control", "set_expression", "wait_anim"])

const TONE: [RegExp, string][] = [
  [/^(text|set_caption|wait_text|menu_switch)$/, "text-emerald-300"],
  [/flag|var|trigger/, "text-violet-300"],
  [/^camera|^fade|^cutscene/, "text-stone-400"],
  [/battle/, "text-red-300"],
  [/item|money|wood|metal|coal|shop/, "text-amber-300"],
  [/goto|^end$|call_event|script/, "text-sky-300"],
]

/** 对白里的控制码 (%S 速度, %C 颜色, %N 换行, %B 选项) → 可读文字 */
export function plainText(s: string, names?: Names | null): string {
  // 控制码同游戏 dialog.gd: %T<物品>. → 物品名, %N 换行, %B<标签>. 选项, %S %C %K 去掉
  return s.replace(/%T(\d+)\./g, (_, id) => names?.items[id] ?? id).replace(/%N/g, "\n").replace(/%B/g, "• ")
    .replace(/%[SCK]\d*/g, "").replace(/%P/g, "")
}

export function actorName(id: number, names: Names | null): string {
  if (id === 65281 || id === 0xff01) return "系统"
  return names?.people[String(id)] || `角色 ${id}`
}

function Arg({ t, v, names, maps, onJump }: { t: string; v: unknown; names: Names | null; maps: Map<number, string>; onJump: (pos: number) => void }) {
  const n = Number(v)
  switch (t) {
    case "r":
      return <button className="text-sky-400 hover:underline" onClick={() => onJump(n)}>→ @{n}</button>
    case "a":
      return <span className="text-sky-200">{actorName(n, names)}</span>
    case "m":
      return <span>{maps.get(n) ?? `地图 ${n}`}</span>
    case "f":
      return <span className="text-violet-300">F{n}</span>
    case "i":
      return <span className="text-amber-200">{names?.items[String(n)] || `物品 ${n}`}</span>
    case "b":
      return <span className="text-red-200">{names?.battles[String(n)] || `战场 ${n}`}</span>
    case "e":
      return <span>事件 {n}</span>
    case "T":
      return <span className="whitespace-pre-wrap text-foreground">「{plainText(String(v), names)}」</span>
    case "F":
    case "R":
    case "P":
      return <span className="text-muted-foreground">[{(v as unknown[]).join(", ")}]</span>
  }
  return <span className="text-muted-foreground">{String(v)}</span>
}

/** 一条指令的显示: 位置、中文名 (悬停看原版说明)、参数换成名字; 对白显示说话人和文字 */
export function InstrLine({ ins, ops, names, maps, onJump, extra }: {
  ins: unknown[]; ops: Record<string, Opcode> | null; names: Names | null; maps: Map<number, string>; onJump: (pos: number) => void
  extra?: Record<string, string> // 本方案的引用 (@npc:1 → 名字)
}) {
  const pos = Number(ins[0])
  const op = String(ins[1])
  const meta = ops?.[op]
  const types = (meta?.operands ?? "").replace(/^a(w{9})T$/, "aT") // 对白: 只显示说话人和文字, 窗口位置参数藏起来
  const args = op === "text" ? [ins[2], ins[ins.length - 1]] : ins.slice(2)
  // 对白: 第一个参数是对话框跟着的角色, 说话人写在文字开头 (「端木老人：%N…」), 有就按文字里的显示
  const said = op === "text" ? /^([^：%\n]{1,12})：/.exec(plainText(String(ins[ins.length - 1]), names).trim()) : null
  const tone = TONE.find(([re]) => re.test(op))?.[1] ?? ""
  return (
    <>
      <span className="w-12 shrink-0 text-right text-muted-foreground/60">{pos}</span>
      <Tooltip>
        <TooltipTrigger asChild>
          <span className={`w-32 shrink-0 truncate font-sans ${tone}`}>{OP_LABEL[op] ?? op}</span>
        </TooltipTrigger>
        <TooltipContent className="max-w-sm">
          <div className="font-mono">{op}{meta ? ` (0x${meta.code})` : ""}</div>
          <div>{meta?.note ?? "（指令表里没有说明）"}</div>
        </TooltipContent>
      </Tooltip>
      <span className="flex min-w-0 flex-1 flex-wrap gap-x-2 font-sans">
        {said ? (
          <><span className="text-sky-200">{said[1]}</span>
            <span className="whitespace-pre-wrap text-foreground">「{plainText(String(ins[ins.length - 1]), names).trim().slice(said[0].length).trim()}」</span></>
        ) : args.map((a, i) => (typeof a === "string" && a.startsWith("@") && extra?.[a])
          ? <span key={i} className="text-orange-300">{extra[a]}</span>
          : <Arg key={i} t={types[i] ?? "w"} v={a} names={names} maps={maps} onJump={onJump} />)}
      </span>
    </>
  )
}

/** 原版事件 (只读): 一条条指令, 中文名 + 参数换成名字; 跳转可以点 */
export function EventViewer({ id, maps, action }: { id: number | null; maps: MapInfo[] | null; action?: (ev: EventInfo) => React.ReactNode }) {
  const [ops, names] = useOpsAndNames()
  const [ev, setEv] = useState<EventInfo | null>(null)
  const [err, setErr] = useState("")
  const [brief, setBrief] = useState(true)
  const [hl, setHl] = useState<number | null>(null)
  const box = useRef<HTMLDivElement>(null)
  const mapNames = useMemo(() => new Map((maps ?? []).map((m) => [m.id, m.title || m.name])), [maps])
  useEffect(() => {
    if (id === null) return
    let alive = true
    setEv(null)
    setErr("")
    api.getEvent(id).then((v) => alive && setEv(v)).catch((e) => alive && setErr(errText(e)))
    return () => {
      alive = false
    }
  }, [id])
  if (id === null) {
    return (
      <Empty className="h-full">
        <EmptyHeader>
          <EmptyTitle>选一个原版事件</EmptyTitle>
          <EmptyDescription>在左边「剧情」里点一个事件，这里按指令显示它的内容（只读）。</EmptyDescription>
        </EmptyHeader>
      </Empty>
    )
  }
  const jump = (pos: number) => {
    setBrief(false)
    setHl(pos)
    setTimeout(() => box.current?.querySelector(`[data-pos="${pos}"]`)?.scrollIntoView({ block: "center", behavior: "smooth" }), 50)
  }
  const code = ev?.code ?? []
  const shown = brief ? code.filter((ins) => !DETAIL.has(String(ins[1]))) : code
  return (
    <div className="flex h-full flex-col">
      <div className="flex flex-wrap items-center gap-2 border-b px-3 py-2 text-sm">
        <LockIcon className="size-3.5 text-muted-foreground" />
        <span className="font-semibold">原版事件 #{id}</span>
        {[...new Set(ev?.triggers ?? [])].slice(0, 3).map((t) => <Badge key={t} variant="secondary">{t.replace(/^\d+_[^_]+_/, "")}</Badge>)}
        {ev?.battles?.map((b) => <Badge key={b} variant="destructive">战斗 {b}</Badge>)}
        {ev && ev.shared && ev.shared.length > 0 && <Badge variant="outline">和事件 {ev.shared.join("、")} 共用</Badge>}
        <span className="text-xs text-muted-foreground">{code.length} 条指令{brief && code.length !== shown.length ? `，显示 ${shown.length} 条` : ""}</span>
        <div className="flex-1" />
        <label className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Switch size="sm" checked={brief} onCheckedChange={setBrief} />只看剧情（隐藏排版和镜头细节）
        </label>
        {ev && action?.(ev)}
      </div>
      {err && <p className="p-3 text-sm text-destructive">{err}</p>}
      {!ev && !err && <div className="space-y-2 p-3">{[0, 1, 2, 3, 4].map((i) => <Skeleton key={i} className="h-6 w-full" />)}</div>}
      {ev && (
        <ScrollArea className="min-h-0 flex-1">
          <div ref={box} className="font-mono text-[12.5px] leading-6">
            {shown.map((ins, k) => (
              <div key={k} data-pos={Number(ins[0])} className={`flex gap-3 px-3 hover:bg-accent/30 ${hl === Number(ins[0]) ? "bg-primary/15" : ""}`}>
                <InstrLine ins={ins} ops={ops} names={names} maps={mapNames} onJump={jump} />
              </div>
            ))}
          </div>
        </ScrollArea>
      )}
    </div>
  )
}
