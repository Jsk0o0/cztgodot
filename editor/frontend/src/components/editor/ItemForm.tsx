import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Badge } from "@/components/ui/badge"
import { Field, FieldDescription, FieldGroup, FieldLabel } from "@/components/ui/field"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog"
import { PackageIcon, Trash2Icon } from "lucide-react"
import { ItemIcon, ItemList, useGameItems } from "./ItemPicker"
import type { GameItem, ModItem, Project } from "@/lib/types"

// 恢复量编码 (同游戏 Formula.amount): 0 不恢复, 1–10000 定值, 10001–10098 百分比, 10099 全满 (>20000 上限倍数 —— 恢复会被上限截住, 等同全满)
type Mode = "none" | "fixed" | "pct" | "full"
function decode(v: number): [Mode, number] {
  if (!v) return ["none", 0]
  if (v > 20000 || v >= 10099) return ["full", 0]
  if (v > 10000) return ["pct", v - 10000]
  return ["fixed", v]
}
function encode(mode: Mode, n: number): number {
  if (mode === "none") return 0
  if (mode === "full") return 10099
  if (mode === "pct") return 10000 + Math.min(98, Math.max(1, Math.round(n)))
  return Math.min(10000, Math.max(1, Math.round(n)))
}

function Recover({ label, v, onChange }: { label: string; v: number; onChange: (v: number) => void }) {
  const [mode, n] = decode(v)
  return (
    <div className="grid grid-cols-[3rem_7rem_1fr] items-center gap-2">
      <span className="text-sm">{label}</span>
      {/* 换方式时数值用该方式的默认值 (定值 200 直接当百分比会变成 98%) */}
      <Select value={mode} onValueChange={(m) => onChange(m === mode ? v : encode(m as Mode, m === "pct" ? 50 : 100))}>
        <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value="none">不恢复</SelectItem>
          <SelectItem value="fixed">定值</SelectItem>
          <SelectItem value="pct">百分比</SelectItem>
          <SelectItem value="full">全满</SelectItem>
        </SelectContent>
      </Select>
      {(mode === "fixed" || mode === "pct") && (
        <div className="flex items-center gap-1.5">
          <Input type="number" value={n} min={1} max={mode === "pct" ? 98 : 10000} className="h-8"
            onChange={(e) => onChange(encode(mode, Number(e.target.value)))} />
          <span className="text-sm text-muted-foreground">{mode === "pct" ? "%" : "点"}</span>
        </div>
      )}
    </div>
  )
}

function Field6(a: number[] | undefined, n: number): number[] {
  const out = [...(a ?? [])]
  while (out.length < n) out.push(0)
  return out.slice(0, n)
}

export function ItemForm({ it, p, onChange, onDelete }: { it: ModItem; p: Project; onChange: (it: ModItem) => void; onDelete: () => void }) {
  const game = useGameItems()
  const base = game?.find((g) => g.id === it.base)
  const heal = base?.sub === 202
  const uses = p.events.filter((e) => JSON.stringify(e.blocks).includes(`"modItem":${it.local}`)).map((e) => e.name)
  const fx1 = Field6(it.fx1 ?? base?.fx1 ?? [], 6)
  const fx2 = Field6(it.fx2 ?? base?.fx2 ?? [], 7)
  return (
    <div className="space-y-4 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-primary"><PackageIcon className="size-4" />物品 @item:{it.local}</div>
      <div className="flex items-center gap-3 rounded-md border bg-muted/30 p-3">
        <ItemIcon icon={base?.icon} className="size-14" />
        <div className="min-w-0 text-sm">
          <div className="font-medium">{it.name || "（未命名）"}</div>
          <div className="text-xs text-muted-foreground">复制自原版「{base?.name ?? it.base}」· {base?.cat ?? "?"}</div>
          <div className="mt-1 flex gap-1.5"><Badge variant="secondary">{it.price} 文</Badge><Badge variant="secondary">卖出 {Math.floor(it.price / 2)} 文</Badge></div>
        </div>
      </div>
      <FieldGroup>
        <Field>
          <FieldLabel htmlFor="itname">名字</FieldLabel>
          <Input id="itname" value={it.name} onChange={(e) => onChange({ ...it, name: e.target.value })} />
        </Field>
        <Field>
          <FieldLabel htmlFor="itdesc">说明</FieldLabel>
          <Textarea id="itdesc" rows={2} value={it.desc} onChange={(e) => onChange({ ...it, desc: e.target.value })} />
          <FieldDescription>道具栏和商店底部显示，一行大约 32 个字。</FieldDescription>
        </Field>
        <Field>
          <FieldLabel htmlFor="itprice">价格</FieldLabel>
          <Input id="itprice" type="number" min={0} value={it.price} onChange={(e) => onChange({ ...it, price: Math.max(0, Number(e.target.value)) })} />
          <FieldDescription>商店买价；卖给商店是一半（同原版）。原版「{base?.name}」是 {base?.price ?? "?"} 文。</FieldDescription>
        </Field>
        {heal && (
          <Field>
            <FieldLabel>恢复效果</FieldLabel>
            <div className="space-y-2">
              <Recover label="生命" v={fx1[0]} onChange={(v) => { const a = [...fx1]; a[0] = v; onChange({ ...it, fx1: a }) }} />
              <Recover label="体力" v={fx1[1]} onChange={(v) => { const a = [...fx1]; a[1] = v; onChange({ ...it, fx1: a }) }} />
              <Recover label="灵力" v={fx2[0]} onChange={(v) => { const a = [...fx2]; a[0] = v; onChange({ ...it, fx2: a }) }} />
            </div>
            <FieldDescription>使用范围、战斗里的演出都照抄原版「{base?.name}」；恢复不会超过上限。</FieldDescription>
          </Field>
        )}
        {!heal && base && <FieldDescription>这类物品的效果照抄原版「{base.name}」，目前只能改名字、说明和价格。</FieldDescription>}
      </FieldGroup>
      {uses.length > 0 ? (
        <p className="text-xs text-muted-foreground">正在被事件 {uses.map((n) => `「${n}」`).join("、")} 使用，先从积木里去掉才能删除。</p>
      ) : (
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button variant="ghost" size="sm" className="text-destructive"><Trash2Icon />删除这个物品</Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>删除物品「{it.name}」？</AlertDialogTitle>
              <AlertDialogDescription>玩家存档里已有的这个物品会变成「失效物品」。</AlertDialogDescription>
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

/** 新建物品: 先选一件原版物品当底子 */
export function NewItemDialog({ open, onOpenChange, p, onCreate }: {
  open: boolean; onOpenChange: (v: boolean) => void; p: Project; onCreate: (base: GameItem) => void
}) {
  const game = useGameItems()
  const [, force] = useState(0)
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md p-0">
        <DialogHeader className="px-4 pt-4">
          <DialogTitle>新建物品</DialogTitle>
          <DialogDescription>先选一件原版物品当底子：分类、图标、使用方式和战斗演出都照抄它，再改名字、说明、价格和恢复量。</DialogDescription>
        </DialogHeader>
        <div className="border-t">
          <ItemList p={p} game={game} mod={false} onPick={(r) => {
            const g = game?.find((x) => x.id === r.item)
            if (g) { onCreate(g); onOpenChange(false); force((x) => x + 1) }
          }} />
        </div>
      </DialogContent>
    </Dialog>
  )
}
