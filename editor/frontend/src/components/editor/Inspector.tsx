import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Switch } from "@/components/ui/switch"
import { Separator } from "@/components/ui/separator"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useState } from "react"
import { ModelPreview } from "./ModelPreview"
import { ItemForm } from "./ItemForm"
import { QuestForm } from "./QuestForm"
import { MonsterForm } from "./MonsterForm"
import { BattleForm } from "./BattleForm"
import { EncounterForm, VarForm } from "./EncounterForm"
import { OrigNpcForm } from "./OrigNpcForm"
import { MemberForm, NewGameForm } from "./MemberForm"
import { SkillForm } from "./SkillForm"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { Empty, EmptyDescription, EmptyHeader, EmptyTitle } from "@/components/ui/empty"
import { Skeleton } from "@/components/ui/skeleton"
import { PencilIcon, Trash2Icon, UserIcon, FlagIcon, PackageOpenIcon, BoxIcon, TriangleAlertIcon, FileUpIcon } from "lucide-react"
import { Spinner } from "@/components/ui/spinner"
import type { MapDetail, CustomModel, Model, Project, Selection, NPC, Flag, Manifest } from "@/lib/types"

type Props = {
  project: Project
  selection: Selection
  models: Model[] | null
  onProject: (p: Project) => void
  onDeleteNpc: (local: number) => void
  onDeleteFlag: (local: number) => void
  onDeleteModel: (local: number) => void
  onDeleteItem: (local: number) => void
  onDeleteQuest: (local: number) => void
  onDeleteMonster: (local: number) => void
  onDeleteBattle: (local: number) => void
  onDeleteVar: (local: number) => void
  detail: MapDetail | null
  onReplaceModel: (local: number) => void
  busy: boolean
  importWarnings: Record<number, string[]>
}

function Section({ icon, title, children }: { icon: React.ReactNode; title: string; children: React.ReactNode }) {
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary">{icon}{title}</div>
      {children}
    </div>
  )
}

function ConfirmDelete({ what, onConfirm }: { what: string; onConfirm: () => void }) {
  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="outline" size="sm" className="w-full text-destructive"><Trash2Icon />删除{what}</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>删除{what}？</AlertDialogTitle>
          <AlertDialogDescription>保存之前还能通过重新打开方案恢复（其他没保存的改动也会一起丢掉）；保存之后就找不回来了。</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>取消</AlertDialogCancel>
          <AlertDialogAction variant="destructive" onClick={onConfirm}>删除</AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}

function ManifestForm({ m, onChange }: { m: Manifest; onChange: (m: Manifest) => void }) {
  return (
    <Section icon={<PackageOpenIcon className="size-4" />} title="mod 信息">
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="mid">ID</FieldLabel>
          <Input id="mid" value={m.id} onChange={(e) => onChange({ ...m, id: e.target.value })} />
          <FieldDescription>作者.名字，只用小写字母、数字、- 和 _。打包分发后不要再改，存档靠它找 mod。</FieldDescription>
        </Field>
        <Field>
          <FieldLabel htmlFor="mname">名称</FieldLabel>
          <Input id="mname" value={m.name} onChange={(e) => onChange({ ...m, name: e.target.value })} />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field>
            <FieldLabel htmlFor="mver">版本</FieldLabel>
            <Input id="mver" value={m.version} onChange={(e) => onChange({ ...m, version: e.target.value })} />
          </Field>
          <Field>
            <FieldLabel htmlFor="mauth">作者</FieldLabel>
            <Input id="mauth" value={m.author} onChange={(e) => onChange({ ...m, author: e.target.value })} />
          </Field>
        </div>
        <Field>
          <FieldLabel htmlFor="mdesc">简介</FieldLabel>
          <Textarea id="mdesc" rows={4} value={m.description} onChange={(e) => onChange({ ...m, description: e.target.value })} />
          <FieldDescription>显示在游戏工坊的详情里。</FieldDescription>
        </Field>
      </FieldGroup>
    </Section>
  )
}

function NpcForm({ n, p, models, onChange, onDelete }: { n: NPC; p: Project; models: Model[] | null; onChange: (n: NPC) => void; onDelete: () => void }) {
  const num = (v: string) => (Number.isFinite(Number(v)) ? Number(v) : 0)
  return (
    <Section icon={<UserIcon className="size-4" />} title="NPC 属性">
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="nname">名字</FieldLabel>
          <Input id="nname" value={n.name} onChange={(e) => onChange({ ...n, name: e.target.value })} />
          <FieldDescription>编号 @npc:{n.local}（游戏里自动分配实际编号）</FieldDescription>
        </Field>
        <Field>
          <FieldLabel>模型</FieldLabel>
          {models === null ? (
            <Skeleton className="h-8 w-full" />
          ) : (
            <Select value={n.model > 0 ? `m:${n.model}` : `a:${n.act}`}
              onValueChange={(v) => onChange(v.startsWith("m:") ? { ...n, model: Number(v.slice(2)) } : { ...n, model: 0, act: Number(v.slice(2)) })}>
              <SelectTrigger className="w-full"><SelectValue placeholder="选择模型" /></SelectTrigger>
              <SelectContent className="max-h-72">
                {p.models.length > 0 && (
                  <SelectGroup>
                    <SelectLabel>自定义模型</SelectLabel>
                    {p.models.map((m) => <SelectItem key={`m${m.local}`} value={`m:${m.local}`}>{m.name}</SelectItem>)}
                  </SelectGroup>
                )}
                <SelectGroup>
                  <SelectLabel>原版模型</SelectLabel>
                  {models.map((m) => <SelectItem key={m.act} value={`a:${m.act}`}>{m.act} · {m.label}</SelectItem>)}
                </SelectGroup>
              </SelectContent>
            </Select>
          )}
          <FieldDescription>{n.model > 0 ? "自定义模型会打包进 mod。" : "引用原版模型编号，不会把原版素材打进 mod。"}</FieldDescription>
        </Field>
        <Field>
          <FieldLabel>位置</FieldLabel>
          <div className="grid grid-cols-3 gap-2">
            {[0, 1, 2].map((i) => (
              <Input key={i} type="number" aria-label={"xyz"[i]} value={Math.round(n.pos[i])}
                onChange={(e) => { const pos = [...n.pos] as NPC["pos"]; pos[i] = num(e.target.value); onChange({ ...n, pos }) }} />
            ))}
          </div>
          <FieldDescription>在地图上用「放置」点地面会自动贴地。</FieldDescription>
        </Field>
        <Field>
          <FieldLabel htmlFor="nface">朝向 {Math.round(n.facing)}°</FieldLabel>
          <input id="nface" type="range" min={0} max={359} value={n.facing} className="w-full accent-primary"
            onChange={(e) => onChange({ ...n, facing: Number(e.target.value) })} />
        </Field>
      </FieldGroup>
      <Separator />
      <FieldGroup>
        <Field orientation="horizontal">
          <Switch id="ntalk" checked={n.talk} onCheckedChange={(v) => onChange({ ...n, talk: v })} />
          <FieldLabel htmlFor="ntalk">可对话</FieldLabel>
        </Field>
        <Field>
          <FieldLabel>对话事件</FieldLabel>
          <Select value={String(n.event)} onValueChange={(v) => onChange({ ...n, event: Number(v) })}>
            <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="0">（无）</SelectItem>
              {p.events.map((e) => <SelectItem key={e.local} value={String(e.local)}>#{e.local} {e.name}</SelectItem>)}
            </SelectContent>
          </Select>
        </Field>
      </FieldGroup>
      <ConfirmDelete what="这个 NPC" onConfirm={onDelete} />
    </Section>
  )
}

function ModelForm({ m, p, warnings, busy, onChange, onDelete, onReplace }: {
  m: CustomModel; p: Project; warnings: string[]; busy: boolean; onChange: (m: CustomModel) => void; onDelete: () => void; onReplace: () => void
}) {
  const [rawH, setRawH] = useState(0)
  const users = [...p.npcs.filter((n) => n.model === m.local), ...p.monsters.filter((x) => x.model === m.local)]
  const animSel = (value: string, set: (v: string) => void, allowNone: boolean) => (
    <Select value={value || "__none"} onValueChange={(v) => set(v === "__none" ? "" : v)}>
      <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
      <SelectContent>
        {allowNone && <SelectItem value="__none">（无）</SelectItem>}
        {m.anims.map((a) => <SelectItem key={a.name} value={a.name}>{a.name} · {a.seconds.toFixed(1)} 秒</SelectItem>)}
      </SelectContent>
    </Select>
  )
  return (
    <Section icon={<BoxIcon className="size-4" />} title={`模型 #${m.local}`}>
      <ModelPreview url={`/project/${m.file}`} scale={m.scale} yaw={m.yaw} anim={m.idle} ground={m.ground ?? 0} onHeight={setRawH} />
      <div className="flex flex-wrap gap-1.5">
        <Badge variant="secondary">{m.triangles.toLocaleString()} 面</Badge>
        <Badge variant="secondary">{(m.size / 1024).toFixed(0)} KB</Badge>
        <Badge variant="secondary">{m.anims.length} 段动画</Badge>
        {rawH > 0 && <Badge variant={rawH * m.scale < 0.8 || rawH * m.scale > 3 ? "destructive" : "secondary"}>游戏里约 {(rawH * m.scale).toFixed(2)} 米高</Badge>}
      </div>
      {m.anims.length === 0 && (
        <Alert>
          <TriangleAlertIcon />
          <AlertDescription>
            这个文件里没有动画（也没有骨骼），人物会一直保持一个姿势。如果原模型有动画，可能选到了同名的静态版文件，点下面「换文件」重新选，或者把带动画的 .glb 拖进窗口。
          </AlertDescription>
        </Alert>
      )}
      {warnings.filter((w) => !w.startsWith("没有动画")).length > 0 && (
        <Alert>
          <TriangleAlertIcon />
          <AlertDescription>{warnings.filter((w) => !w.startsWith("没有动画")).map((w) => <div key={w}>{w}</div>)}</AlertDescription>
        </Alert>
      )}
      <div className="flex items-center justify-between gap-2 text-xs text-muted-foreground">
        <span className="truncate" title={m.file}>{m.file}</span>
        <Button variant="outline" size="sm" disabled={busy} onClick={onReplace}>
          {busy ? <Spinner /> : <FileUpIcon />}换文件
        </Button>
      </div>
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="mdname">名字</FieldLabel>
          <Input id="mdname" value={m.name} onChange={(e) => onChange({ ...m, name: e.target.value })} />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field>
            <FieldLabel htmlFor="mdscale">缩放</FieldLabel>
            <Input id="mdscale" type="number" step="0.05" min="0.05" value={m.scale} onChange={(e) => onChange({ ...m, scale: Number(e.target.value) })} />
          </Field>
          <Field>
            <FieldLabel>朝向修正</FieldLabel>
            <Select value={String(m.yaw)} onValueChange={(v) => onChange({ ...m, yaw: Number(v) })}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>{[0, 90, 180, 270].map((d) => <SelectItem key={d} value={String(d)}>{d}°</SelectItem>)}</SelectContent>
            </Select>
          </Field>
        </div>
        <FieldDescription>游戏里 1 单位 = 1 米，人物一般 1.5–1.8 米。白色箭头要指向人物的脸，不对就调「朝向修正」。</FieldDescription>
        <Field>
          <FieldLabel>待机动画（站着时）</FieldLabel>
          {animSel(m.idle, (v) => onChange({ ...m, idle: v }), true)}
        </Field>
        <Field>
          <FieldLabel>行走动画（走路时）</FieldLabel>
          {animSel(m.walk, (v) => onChange({ ...m, walk: v }), true)}
          <FieldDescription>没有就保持待机动画。</FieldDescription>
        </Field>
      </FieldGroup>
      {users.length > 0 ? (
        <p className="text-xs text-muted-foreground">正在被 {users.map((n) => `「${n.name}」`).join("、")} 使用，先给它们换模型才能删除。</p>
      ) : (
        <ConfirmDelete what="这个模型" onConfirm={onDelete} />
      )}
    </Section>
  )
}

function FlagForm({ f, p, onChange, onDelete }: { f: Flag; p: Project; onChange: (f: Flag) => void; onDelete: () => void }) {
  const uses = p.events.filter((e) => JSON.stringify(e.blocks).includes(`"flag":${f.local}`)).map((e) => e.name)
  return (
    <Section icon={<FlagIcon className="size-4" />} title={`旗标 F${f.local}`}>
      <Field>
        <FieldLabel htmlFor="fname">名字</FieldLabel>
        <Input id="fname" value={f.name} onChange={(e) => onChange({ ...f, name: e.target.value })} />
        <FieldDescription>旗标是一个开 / 关的记号，跟着存档保存。常用来记「已经领过奖励」。</FieldDescription>
      </Field>
      <p className="text-sm text-muted-foreground">{uses.length ? `用到它的事件：${uses.join("、")}` : "还没有事件用到它。"}</p>
      <ConfirmDelete what="这个旗标" onConfirm={onDelete} />
    </Section>
  )
}

export function Inspector({ project: p, selection, models, onProject, onDeleteNpc, onDeleteFlag, onDeleteModel, onDeleteItem, onDeleteQuest, onDeleteMonster, onDeleteBattle, onDeleteVar, detail, onReplaceModel, busy, importWarnings }: Props) {
  let body: React.ReactNode = null
  if (selection?.kind === "manifest") {
    body = <ManifestForm m={p.manifest} onChange={(manifest) => onProject({ ...p, manifest })} />
  } else if (selection?.kind === "npc") {
    const n = p.npcs.find((x) => x.local === selection.local)
    if (n) body = <NpcForm n={n} p={p} models={models} onDelete={() => onDeleteNpc(n.local)}
      onChange={(nn) => onProject({ ...p, npcs: p.npcs.map((x) => (x.local === nn.local ? nn : x)) })} />
  } else if (selection?.kind === "model") {
    const m = p.models.find((x) => x.local === selection.local)
    if (m) body = <ModelForm m={m} p={p} warnings={importWarnings[m.local] ?? []} busy={busy} onDelete={() => onDeleteModel(m.local)} onReplace={() => onReplaceModel(m.local)}
      onChange={(nm) => onProject({ ...p, models: p.models.map((x) => (x.local === nm.local ? nm : x)) })} />
  } else if (selection?.kind === "quest") {
    const q = p.quests.find((x) => x.local === selection.local)
    if (q) body = <QuestForm q={q} p={p} onDelete={() => onDeleteQuest(q.local)}
      onChange={(nq) => onProject({ ...p, quests: p.quests.map((x) => (x.local === nq.local ? nq : x)) })} />
  } else if (selection?.kind === "item") {
    const it = p.items.find((x) => x.local === selection.local)
    if (it) body = <ItemForm it={it} p={p} onDelete={() => onDeleteItem(it.local)}
      onChange={(ni) => onProject({ ...p, items: p.items.map((x) => (x.local === ni.local ? ni : x)) })} />
  } else if (selection?.kind === "monster") {
    const m = p.monsters.find((x) => x.local === selection.local)
    if (m) body = <MonsterForm m={m} p={p} onDelete={() => onDeleteMonster(m.local)}
      onChange={(nm) => onProject({ ...p, monsters: p.monsters.map((x) => (x.local === nm.local ? nm : x)) })} />
  } else if (selection?.kind === "battle") {
    const b = p.battles.find((x) => x.local === selection.local)
    if (b) body = <BattleForm b={b} p={p} onDelete={() => onDeleteBattle(b.local)}
      onChange={(nb) => onProject({ ...p, battles: p.battles.map((x) => (x.local === nb.local ? nb : x)) })} />
  } else if (selection?.kind === "var") {
    const v = p.vars.find((x) => x.local === selection.local)
    if (v) body = <VarForm v={v} p={p} onDelete={() => onDeleteVar(v.local)}
      onChange={(nv) => onProject({ ...p, vars: p.vars.map((x) => (x.local === nv.local ? nv : x)) })} />
  } else if (selection?.kind === "encounters") {
    body = <EncounterForm map={selection.map} detail={detail} p={p} onChange={(encounters) => onProject({ ...p, encounters })} />
  } else if (selection?.kind === "member") {
    body = <MemberForm id={selection.id} p={p} models={models} onChange={(characters) => onProject({ ...p, characters })} />
  } else if (selection?.kind === "newgame") {
    body = <NewGameForm p={p} onChange={(newGame) => onProject({ ...p, newGame })} />
  } else if (selection?.kind === "skill") {
    const sk = p.skills.find((x) => x.local === selection.local)
    if (sk) body = <SkillForm s={sk} p={p} onChange={(ns) => onProject({ ...p, skills: p.skills.map((x) => (x.local === ns.local ? ns : x)) })}
      onDelete={() => onProject({ ...p, skills: p.skills.filter((x) => x.local !== sk.local) })} />
  } else if (selection?.kind === "skill_edit") {
    const se = p.skillEdits.find((x) => x.id === selection.id)
    if (se) body = <SkillForm edit={se} p={p}
      onEdit={(ne) => onProject({ ...p, skillEdits: ne ? p.skillEdits.map((x) => (x.id === ne.id ? ne : x)) : p.skillEdits.filter((x) => x.id !== se.id) })} />
  } else if (selection?.kind === "orig_npc") {
    body = <OrigNpcForm map={selection.map} actor={selection.actor} detail={detail} p={p} models={models} onChange={(npcEdits) => onProject({ ...p, npcEdits })} />
  } else if (selection?.kind === "override") {
    const o = p.overrides.find((x) => x.id === selection.id)
    if (o) body = (
      <Section icon={<PencilIcon className="size-4" />} title={`改原版事件 #${o.id}`}>
        <Field>
          <FieldLabel htmlFor="ovname">备注名</FieldLabel>
          <Input id="ovname" value={o.name} onChange={(e) => onProject({ ...p, overrides: p.overrides.map((x) => (x.id === o.id ? { ...o, name: e.target.value } : x)) })} />
          <FieldDescription>只在编辑器里显示。</FieldDescription>
        </Field>
        <p className="text-sm text-muted-foreground">
          游戏加载这个方案时，原版事件 #{o.id} 整段换成下面的指令（{o.code.length} 条）。原版文件不会被改；不加载方案就是原版。
        </p>
        <ConfirmDelete what="这项修改（恢复原版）" onConfirm={() => onProject({ ...p, overrides: p.overrides.filter((x) => x.id !== o.id) })} />
      </Section>
    )
  } else if (selection?.kind === "flag") {
    const f = p.flags.find((x) => x.local === selection.local)
    if (f) body = <FlagForm f={f} p={p} onDelete={() => onDeleteFlag(f.local)}
      onChange={(nf) => onProject({ ...p, flags: p.flags.map((x) => (x.local === nf.local ? nf : x)) })} />
  }
  if (!body) {
    return (
      <Empty className="h-full">
        <EmptyHeader>
          <EmptyTitle>没有选中内容</EmptyTitle>
          <EmptyDescription>选中左边的 mod 信息、NPC、物品、怪物、战斗或旗标，在这里编辑属性。</EmptyDescription>
        </EmptyHeader>
      </Empty>
    )
  }
  return <ScrollArea className="h-full">{body}</ScrollArea>
}
