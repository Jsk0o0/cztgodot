import { Input } from "@/components/ui/input"
import { Switch } from "@/components/ui/switch"
import { Button } from "@/components/ui/button"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { ScrollTextIcon, Trash2Icon } from "lucide-react"
import type { Project, Quest } from "@/lib/types"

const QUEST_FLAG_BASE = 900 // 同 Go 端 project.QuestFlagBase

export function QuestForm({ q, p, onChange, onDelete }: { q: Quest; p: Project; onChange: (q: Quest) => void; onDelete: () => void }) {
  const uses = p.events.filter((e) => JSON.stringify(e.blocks).includes(`"quest":${q.local}`)).map((e) => e.name)
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary"><ScrollTextIcon className="size-4" />任务 #{q.local}</div>
      <div className="rounded-md border bg-muted/30 p-3 text-sm">
        <div className="mb-1 text-xs text-muted-foreground">记载 ·「事」页里显示为</div>
        <div className="font-serif text-[#c96a45]">{q.main ? "★" : "☆"}{q.title || "（任务名）"}</div>
      </div>
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="qtitle">任务名</FieldLabel>
          <Input id="qtitle" value={q.title} onChange={(e) => onChange({ ...q, title: e.target.value })} />
          <FieldDescription>一句话说清楚要做什么，例：带 3 株草药给熊掌柜。</FieldDescription>
        </Field>
        <Field orientation="horizontal">
          <Switch id="qmain" checked={q.main} onCheckedChange={(v) => onChange({ ...q, main: v })} />
          <FieldLabel htmlFor="qmain">主线任务（★）</FieldLabel>
        </Field>
        <FieldDescription>
          用事件里的「任务」积木接受 / 完成，「如果任务」积木判断进度。编辑器自动用旗标 F{QUEST_FLAG_BASE + q.local}（已接受）和 F{QUEST_FLAG_BASE + 50 + q.local}（已完成）记录，跟着存档保存。
        </FieldDescription>
      </FieldGroup>
      {uses.length > 0 ? (
        <p className="text-xs text-muted-foreground">正在被事件 {uses.map((n) => `「${n}」`).join("、")} 使用，先从积木里去掉才能删除。</p>
      ) : (
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button variant="ghost" size="sm" className="text-destructive"><Trash2Icon />删除这个任务</Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>删除任务「{q.title}」？</AlertDialogTitle>
              <AlertDialogDescription>玩家存档里的任务进度会留在存档里，但记载页不再显示。</AlertDialogDescription>
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
