import { Badge } from "@/components/ui/badge"
import { Empty, EmptyDescription, EmptyHeader, EmptyTitle } from "@/components/ui/empty"
import { ScrollArea } from "@/components/ui/scroll-area"
import { BookOpenIcon, LockIcon } from "lucide-react"
import type { StoryEvent } from "@/lib/types"

/** 原版事件概要 (只读): 地点、触发方式、任务进度 */
export function OrigInfo({ e, hasProject, snapMap }: { e: StoryEvent | null; hasProject: boolean; snapMap?: string | null }) {
  if (!e) {
    return (
      <Empty className="h-full">
        <EmptyHeader>
          <EmptyTitle>原版内容只能看</EmptyTitle>
          <EmptyDescription>在左边选剧情事件或地图浏览。{hasProject ? "要改它，切回「方案」。" : "要修改，先新建一个方案。"}</EmptyDescription>
        </EmptyHeader>
      </Empty>
    )
  }
  return (
    <ScrollArea className="h-full">
      <div className="space-y-4 p-4 text-sm">
        <div className="flex items-center gap-2 font-semibold text-primary"><BookOpenIcon className="size-4" />原版事件 #{e.id}</div>
        <div className="text-base">{e.name || e.trig || "（没有名字）"}</div>
        <dl className="grid grid-cols-[4.5rem_1fr] gap-x-2 gap-y-1.5">
          <dt className="text-muted-foreground">地点</dt>
          <dd>{snapMap ?? e.map}{snapMap ? <span className="text-xs text-emerald-300"> （剧情快照）</span> : e.mid ? <span className="text-muted-foreground"> · {e.mid}</span> : null}</dd>
          {e.reached && <><dt className="text-muted-foreground">游玩时间</dt><dd>{Math.floor(e.time / 3600)} 小时 {Math.floor((e.time % 3600) / 60)} 分（自动通关）</dd></>}
          {e.trig && <><dt className="text-muted-foreground">触发</dt><dd>{e.trig}</dd></>}
          {e.talk > 0 && <><dt className="text-muted-foreground">对白</dt><dd>{e.talk} 句</dd></>}
        </dl>
        {(e.acc?.length ?? 0) > 0 && (
          <div className="space-y-1"><div className="text-muted-foreground">接受任务</div>
            <div className="flex flex-wrap gap-1">{e.acc!.map((q) => <Badge key={q} variant="secondary">{q}</Badge>)}</div></div>
        )}
        {(e.comp?.length ?? 0) > 0 && (
          <div className="space-y-1"><div className="text-muted-foreground">完成任务</div>
            <div className="flex flex-wrap gap-1">{e.comp!.map((q) => <Badge key={q} variant="outline">{q}</Badge>)}</div></div>
        )}
        {e.first && <p className="rounded-md border bg-muted/30 p-2 text-muted-foreground">{e.first}</p>}
        <p className="flex items-center gap-1.5 text-xs text-muted-foreground"><LockIcon className="size-3" />原版内容只读，下方是它的全部指令。</p>
      </div>
    </ScrollArea>
  )
}
