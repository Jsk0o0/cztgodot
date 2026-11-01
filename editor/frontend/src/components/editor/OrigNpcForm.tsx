import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Switch } from "@/components/ui/switch"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { RotateCcwIcon, TriangleAlertIcon, UserIcon } from "lucide-react"
import type { MapDetail, Model, NpcEdit, Project } from "@/lib/types"

/** 原版地图上的 NPC: 在方案里改名字 / 模型 / 朝向 / 对话事件 / 位置, 或删掉; 只记改了的项 */
export function OrigNpcForm({ map, actor, detail, p, models, onChange }: {
  map: number; actor: number; detail: MapDetail | null; p: Project; models: Model[] | null; onChange: (edits: NpcEdit[]) => void
}) {
  const orig = detail?.id === map ? detail.npcs?.find((n) => n.actor === actor) : undefined
  const ed: NpcEdit = p.npcEdits.find((e) => e.map === map && e.actor === actor) ?? { map, actor }
  const others = p.npcEdits.filter((e) => !(e.map === map && e.actor === actor))
  const set = (patch: Partial<NpcEdit>) => {
    const next = { ...ed, ...patch }
    // 和原版一样的项不记
    const changed = Object.keys(next).some((k) => !["map", "actor"].includes(k) && next[k as keyof NpcEdit] !== undefined)
    onChange(changed ? [...others, next] : others)
  }
  if (!orig) {
    return <p className="p-4 text-sm text-muted-foreground">正在读地图…</p>
  }
  const pos = ed.pos ?? orig.pos
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary"><UserIcon className="size-4" />原版 NPC · 角色 {actor}</div>
      <p className="text-xs text-muted-foreground">原版：{orig.name || "无名"} · 模型 {orig.act} · 对话事件 {orig.event || "无"}。只改你动过的项，其余照原版（出现条件、走动等）。</p>
      <FieldGroup>
        <Field orientation="horizontal">
          <FieldLabel htmlFor="rm">从地图上删掉</FieldLabel>
          <Switch id="rm" checked={!!ed.remove} onCheckedChange={(v) => set({ remove: v || undefined })} />
        </Field>
        {ed.remove && (
          <Alert>
            <TriangleAlertIcon />
            <AlertDescription>要是剧情需要和它说话（任务、开门等），删掉后剧情可能走不下去。</AlertDescription>
          </Alert>
        )}
        {!ed.remove && (
          <>
            <Field>
              <FieldLabel htmlFor="on">名字</FieldLabel>
              <Input id="on" value={ed.name ?? orig.name} onChange={(e) => set({ name: e.target.value === orig.name ? undefined : e.target.value })} />
              <FieldDescription>对话框标题显示的名字（原版里所有用到这个角色的地方都会变）。</FieldDescription>
            </Field>
            <Field>
              <FieldLabel>模型</FieldLabel>
              <Select value={ed.model ? `m${ed.model}` : String(ed.act ?? orig.act)}
                onValueChange={(v) => v.startsWith("m") ? set({ model: Number(v.slice(1)), act: undefined })
                  : set({ model: undefined, act: Number(v) === orig.act ? undefined : Number(v) })}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent className="max-h-80">
                  {p.models.length > 0 && (
                    <SelectGroup><SelectLabel>本方案的模型</SelectLabel>
                      {p.models.map((m) => <SelectItem key={m.local} value={`m${m.local}`}>{m.name}</SelectItem>)}
                    </SelectGroup>
                  )}
                  <SelectGroup><SelectLabel>原版模型</SelectLabel>
                    {!models?.some((m) => m.act === orig.act) && <SelectItem value={String(orig.act)}>原版 {orig.act}</SelectItem>}
                    {(models ?? []).map((m) => <SelectItem key={m.act} value={String(m.act)}>{m.label} · {m.act}{m.act === orig.act ? "（原版）" : ""}</SelectItem>)}
                  </SelectGroup>
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor="of">朝向</FieldLabel>
              <Input id="of" type="number" min={0} max={359} value={ed.facing ?? orig.facing}
                onChange={(e) => { const v = ((Math.round(Number(e.target.value)) % 360) + 360) % 360; set({ facing: v === orig.facing ? undefined : v }) }} />
            </Field>
            <Field>
              <FieldLabel>对话事件</FieldLabel>
              <Select value={ed.modEvent ? `m${ed.modEvent}` : "orig"}
                onValueChange={(v) => v === "orig" ? set({ modEvent: undefined, event: undefined }) : set({ modEvent: Number(v.slice(1)), event: undefined })}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="orig">原版事件 #{orig.event || "无"}{p.overrides.some((o) => o.id === orig.event) ? "（方案里改过）" : ""}</SelectItem>
                  {p.events.map((e) => <SelectItem key={e.local} value={`m${e.local}`}>本方案：{e.name}</SelectItem>)}
                </SelectContent>
              </Select>
              <FieldDescription>想改它原来说的话：切到「原版」找到事件 #{orig.event} 复制到方案修改；想整个换掉：选一个本方案的事件。</FieldDescription>
            </Field>
            <Field>
              <FieldLabel>位置</FieldLabel>
              <p className="text-sm">{pos.map((x) => Math.round(x)).join(", ")}{ed.pos ? <span className="text-xs text-primary"> （挪过）</span> : null}</p>
              <FieldDescription>用地图上方的「移动 NPC」，再点地面放到新位置。</FieldDescription>
            </Field>
          </>
        )}
      </FieldGroup>
      {ed !== undefined && p.npcEdits.some((e) => e.map === map && e.actor === actor) && (
        <Button variant="outline" size="sm" className="w-full" onClick={() => onChange(others)}><RotateCcwIcon />恢复原版</Button>
      )}
    </div>
  )
}
