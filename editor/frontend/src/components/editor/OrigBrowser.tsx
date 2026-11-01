import { useEffect, useMemo, useState } from "react"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Input } from "@/components/ui/input"
import { Skeleton } from "@/components/ui/skeleton"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { BookOpenIcon, ChevronRightIcon, MapIcon, MessageSquareIcon, SearchIcon } from "lucide-react"
import { api, errText } from "@/lib/api"
import { cn } from "@/lib/utils"
import type { Chapter, MapInfo, StoryEvent, Task } from "@/lib/types"

let chCache: Promise<Chapter[]> | null = null

const KINDS = ["城镇", "户外", "室内", "迷宫", "地图", "剧情"]

function EventRow({ e, active, onClick, noMap }: { e: StoryEvent; active: boolean; onClick: () => void; noMap?: boolean }) {
  return (
    <button onClick={onClick} data-orig-event={e.id}
      className={cn("flex w-full flex-col rounded-md px-2 py-1 text-left text-sm hover:bg-sidebar-accent/60",
        active && "bg-sidebar-accent ring-1 ring-primary/40", !e.reached && "opacity-55")}>
      <span className="flex items-center gap-1.5">
        <span className="text-xs text-muted-foreground">#{e.id}</span>
        <span className="min-w-0 flex-1 truncate">{noMap ? (e.name || e.first || e.trig) : (e.name || e.trig || e.map)}</span>
        {e.talk > 0 && <MessageSquareIcon className="size-3 text-muted-foreground" />}
        {!e.reached && <span className="text-[10px] text-muted-foreground">没经过</span>}
      </span>
      {(noMap ? (e.name ? e.first : "") : "x") && (
        <span className="truncate text-xs text-muted-foreground">{noMap ? e.first : `${e.map}${e.first ? ` · ${e.first}` : ""}`}</span>
      )}
    </button>
  )
}

/** 按地点分段列事件 (同一地点连续的放在一个地点小标题下) */
function ByPlace({ evs, eventId, onEvent }: { evs: StoryEvent[]; eventId: number | null; onEvent: (e: StoryEvent) => void }) {
  return (
    <>
      {evs.map((e, i) => (
        <div key={e.id}>
          {(i === 0 || evs[i - 1].map !== e.map) && (
            <div className="flex items-center gap-1 px-2 pt-1.5 text-[11px] text-muted-foreground"><MapIcon className="size-3" />{e.map}</div>
          )}
          <EventRow e={e} active={eventId === e.id} onClick={() => onEvent(e)} noMap />
        </div>
      ))}
    </>
  )
}

/** 收起来的一类 (对话 / 其他触发点), 选中的事件在里面就自动展开 */
function Fold({ label, evs, eventId, onEvent }: { label: string; evs: StoryEvent[]; eventId: number | null; onEvent: (e: StoryEvent) => void }) {
  const [open, setOpen] = useState(false)
  if (!evs.length) return null
  const has = eventId !== null && evs.some((e) => e.id === eventId)
  return (
    <Collapsible open={open || has} onOpenChange={setOpen}>
      <CollapsibleTrigger className="flex w-full items-center gap-1 px-2 pt-1 text-left text-[11px] text-muted-foreground hover:text-foreground">
        <ChevronRightIcon className={cn("size-3 transition-transform", (open || has) && "rotate-90")} />{label}（{evs.length}）
      </CollapsibleTrigger>
      <CollapsibleContent className="pl-2 opacity-90"><ByPlace evs={evs} eventId={eventId} onEvent={onEvent} /></CollapsibleContent>
    </Collapsible>
  )
}

/** 一个任务: 任务名 → 推进剧情的事件 (按地点分段) + 收起来的「支线」「路人对话」「其他触发点」 */
function TaskBlock({ t, eventId, onEvent }: { t: Task; eventId: number | null; onEvent: (e: StoryEvent) => void }) {
  const [open, setOpen] = useState(true)
  const has = eventId !== null && t.events.some((e) => e.id === eventId)
  const story = t.events.filter((e) => e.kind === "story")
  const side = t.events.filter((e) => e.kind === "side")
  const talk = t.events.filter((e) => e.kind === "talk")
  const other = t.events.filter((e) => e.kind === "other")
  return (
    <Collapsible open={open || has} onOpenChange={setOpen}>
      <CollapsibleTrigger className="flex w-full items-center gap-1.5 rounded-md px-1.5 py-1 text-left hover:bg-sidebar-accent/60">
        <ChevronRightIcon className={cn("size-3.5 shrink-0 text-muted-foreground transition-transform", (open || has) && "rotate-90")} />
        <span className={cn("shrink-0 text-xs", t.main ? "text-amber-300" : "text-sky-300")}>{t.title ? (t.main ? "★" : "☆") : "·"}</span>
        <span className="min-w-0 flex-1 truncate text-sm">{t.title || "（没有进行中的主线任务）"}</span>
        {t.done && <span className="text-[10px] text-emerald-400">完成</span>}
      </CollapsibleTrigger>
      <CollapsibleContent className="pl-5">
        {story.length > 0 ? <ByPlace evs={story} eventId={eventId} onEvent={onEvent} />
          : <p className="px-2 py-1 text-[11px] text-muted-foreground">这一步没有推进剧情的事件</p>}
        <Fold label="顺路的支线任务" evs={side} eventId={eventId} onEvent={onEvent} />
        <Fold label="路人对话（不影响剧情）" evs={talk} eventId={eventId} onEvent={onEvent} />
        <Fold label="其他触发点 / 旁白 / 出入口（不影响剧情）" evs={other} eventId={eventId} onEvent={onEvent} />
      </CollapsibleContent>
    </Collapsible>
  )
}

/** 原版内容 (只读): 剧情线路按章节 / 地图列表 */
export function OrigBrowser({ maps, mapId, eventId, onMap, onEvent }: {
  maps: MapInfo[] | null; mapId: number | null; eventId: number | null; onMap: (id: number) => void; onEvent: (e: StoryEvent) => void
}) {
  const [chs, setChs] = useState<Chapter[] | null>(null)
  const [err, setErr] = useState("")
  const [q, setQ] = useState("")
  const [open, setOpen] = useState<Record<string, boolean>>({ ch01: true })
  useEffect(() => {
    chCache ??= api.listChapters()
    chCache.then(setChs).catch((e) => { chCache = null; setErr(errText(e)) })
  }, [])
  // 从别处选中的事件 (例: 开发 URL、以后的跳转): 展开它所在的章节并滚到它
  useEffect(() => {
    if (eventId === null || !chs) return
    const c = chs.find((x) => x.events.some((e) => e.id === eventId))
    if (c && !open[c.key]) setOpen((o) => ({ ...o, [c.key]: true }))
    setTimeout(() => {   // 只滚列表自己 (scrollIntoView 会连外层面板一起滚, 把标签页和搜索框滚出去)
      const el = document.querySelector<HTMLElement>(`[data-orig-event="${eventId}"]`)
      const vp = el?.closest<HTMLElement>("[data-slot=scroll-area-viewport]")
      if (el && vp) vp.scrollTop += el.getBoundingClientRect().top - vp.getBoundingClientRect().top - vp.clientHeight / 2
    }, 80)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [eventId, chs])
  const match = useMemo(() => {
    const s = q.trim()
    if (!s) return null
    return (e: StoryEvent) => String(e.id) === s || [e.name, e.trig, e.map, e.first].some((x) => x?.includes(s))
  }, [q])
  return (
    <Tabs defaultValue="story" className="flex h-full flex-col gap-0 bg-sidebar">
      <TabsList className="mx-2 mt-2 grid w-[calc(100%-1rem)] grid-cols-2">
        <TabsTrigger value="story"><BookOpenIcon />剧情</TabsTrigger>
        <TabsTrigger value="maps"><MapIcon />地图</TabsTrigger>
      </TabsList>
      <TabsContent value="story" className="flex min-h-0 flex-1 flex-col">
        {chs && <p className="mx-3 mt-1 text-[11px] text-muted-foreground">
          {chs.some((c) => c.events.some((e) => e.reached)) ? "按真实游玩顺序（自动通关录的剧情快照）" : "还没有剧情快照：按事件编号排列"}
        </p>}
        <div className="relative m-2">
          <SearchIcon className="absolute top-2.5 left-2.5 size-4 text-muted-foreground" />
          <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="搜事件号、地点、对白…" className="pl-8" />
        </div>
        <ScrollArea className="min-h-0 flex-1">
          <div className="space-y-1 px-2 pb-3">
            {err && <p className="px-2 text-sm text-destructive">{err}</p>}
            {!chs && !err && [0, 1, 2, 3, 4, 5].map((i) => <Skeleton key={i} className="h-9 w-full" />)}
            {chs?.map((c) => {
              const list = match ? c.events.filter(match) : c.events
              if (match && list.length === 0) return null
              const isOpen = !!match || !!open[c.key]
              return (
                <Collapsible key={c.key} open={isOpen} onOpenChange={(v) => setOpen({ ...open, [c.key]: v })}>
                  <CollapsibleTrigger className="flex w-full items-center gap-1.5 rounded-md px-1.5 py-1.5 text-left hover:bg-sidebar-accent/60">
                    <ChevronRightIcon className={cn("size-4 shrink-0 text-muted-foreground transition-transform", isOpen && "rotate-90")} />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium">{c.title}</span>
                      {c.sub && <span className="block truncate text-xs text-muted-foreground">{c.sub}</span>}
                    </span>
                    <span className="text-xs text-muted-foreground">{list.length}</span>
                  </CollapsibleTrigger>
                  <CollapsibleContent className="space-y-0.5 pl-3">
                    {!match && c.tasks && c.tasks.length > 0 ? (
                      <>
                        {c.tasks.map((t, i) => <TaskBlock key={i} t={t} eventId={eventId} onEvent={onEvent} />)}
                        {c.side && c.side.length > 0 && (
                          <>
                            <div className="px-2 pt-2 pb-1 text-[11px] text-muted-foreground">支线任务</div>
                            {c.side.map((t, i) => <TaskBlock key={`s${i}`} t={{ ...t, main: false }} eventId={eventId} onEvent={onEvent} />)}
                          </>
                        )}
                        {list.some((e) => !e.reached) && (
                          <Collapsible>
                            <CollapsibleTrigger className="flex w-full items-center gap-1.5 px-1.5 pt-2 pb-1 text-left text-[11px] text-muted-foreground hover:text-foreground">
                              <ChevronRightIcon className="size-3.5" />这一章没经过的事件（{list.filter((e) => !e.reached).length}）：调试 / 删减内容，或通关路线没走的
                            </CollapsibleTrigger>
                            <CollapsibleContent className="pl-3 opacity-80">
                              {list.filter((e) => !e.reached).map((e) => <EventRow key={e.id} e={e} active={eventId === e.id} onClick={() => onEvent(e)} />)}
                            </CollapsibleContent>
                          </Collapsible>
                        )}
                      </>
                    ) : list.map((e, i) => (
                      <div key={e.id}>
                        {!e.reached && (i === 0 || list[i - 1].reached) && c.group === "剧情" && (
                          <div className="px-2 pt-2 pb-1 text-[11px] text-muted-foreground">这一章没经过的事件：调试 / 删减内容，或通关路线没走的</div>
                        )}
                        <EventRow e={e} active={eventId === e.id} onClick={() => onEvent(e)} />
                      </div>
                    ))}
                  </CollapsibleContent>
                </Collapsible>
              )
            })}
          </div>
        </ScrollArea>
      </TabsContent>
      <TabsContent value="maps" className="min-h-0 flex-1">
        <ScrollArea className="h-full">
          <div className="space-y-2 px-2 pb-3">
            {!maps && [0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-7 w-full" />)}
            {maps && KINDS.map((k) => {
              const list = maps.filter((m) => m.kind === k)
              if (!list.length) return null
              return (
                <div key={k}>
                  <div className="px-2 pt-2 pb-1 text-xs text-muted-foreground">{k}</div>
                  {list.map((m) => (
                    <button key={m.id} onClick={() => onMap(m.id)}
                      className={cn("flex h-8 w-full items-center gap-2 rounded-md px-2 text-left text-sm hover:bg-sidebar-accent/60",
                        mapId === m.id && "bg-sidebar-accent ring-1 ring-primary/40")}>
                      <MapIcon className="size-4 text-primary/80" />
                      <span className="min-w-0 flex-1 truncate">{m.title || m.name}</span>
                      <span className="text-xs text-muted-foreground">{m.id}</span>
                    </button>
                  ))}
                </div>
              )
            })}
          </div>
        </ScrollArea>
      </TabsContent>
    </Tabs>
  )
}
