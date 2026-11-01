import { useEffect, useState } from "react"
import { Button } from "@/components/ui/button"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { Skeleton } from "@/components/ui/skeleton"
import { ChevronsUpDownIcon } from "lucide-react"
import { api } from "@/lib/api"
import type { GameItem, ItemRef, ModItem, Project } from "@/lib/types"

// 原版物品只读一次, 全编辑器共用
let cache: Promise<GameItem[]> | null = null
export function useGameItems(): GameItem[] | null {
  const [items, setItems] = useState<GameItem[] | null>(null)
  useEffect(() => {
    let alive = true
    cache ??= api.listItems().catch((e) => {
      cache = null
      throw e
    })
    cache.then((v) => alive && setItems(v)).catch(() => alive && setItems([]))
    return () => {
      alive = false
    }
  }, [])
  return items
}

export function ItemIcon({ icon, className = "size-6" }: { icon?: string; className?: string }) {
  if (!icon) return <span className={`${className} shrink-0 rounded bg-muted`} />
  return <img src={`/gamedata/${icon}`} alt="" className={`${className} shrink-0 object-contain`} />
}

/** 引用显示用: 名字 + 图标 (本 mod 物品用它复制的原版物品图标) */
export function describeRef(ref: ItemRef, p: Project, game: GameItem[] | null): { name: string; icon?: string; price?: number } {
  if (ref.modItem) {
    const m = p.items.find((x) => x.local === ref.modItem)
    const base = game?.find((g) => g.id === m?.base)
    return { name: m?.name ?? `（物品 #${ref.modItem} 已删除）`, icon: base?.icon, price: m?.price }
  }
  const g = game?.find((x) => x.id === ref.item)
  return { name: g?.name ?? (ref.item ? `原版物品 ${ref.item}` : "选择物品"), icon: g?.icon, price: g?.price }
}

const CAT_ORDER = ["恢复", "辅助", "攻击", "武器", "防具", "饰品", "鞋", "法宝", "素材", "剧情"]

/** 物品列表 (可搜索): 本 mod 物品在最上面, 原版按分类分组 */
export function ItemList({ p, game, onPick, mod = true, selected }: {
  p: Project; game: GameItem[] | null; onPick: (r: ItemRef) => void; mod?: boolean; selected?: ItemRef
}) {
  if (game === null) {
    return <div className="space-y-2 p-3">{[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-7 w-full" />)}</div>
  }
  const isSel = (r: ItemRef) => !!selected && (r.modItem ? selected.modItem === r.modItem : !selected.modItem && selected.item === r.item)
  return (
    <Command filter={(value, search) => (value.toLowerCase().includes(search.toLowerCase()) ? 1 : 0)}>
      <CommandInput placeholder="搜索物品名或编号…" />
      <CommandList className="max-h-80">
        <CommandEmpty>找不到这个物品</CommandEmpty>
        {mod && p.items.length > 0 && (
          <CommandGroup heading="本 mod 的物品">
            {p.items.map((m: ModItem) => {
              const base = game.find((g) => g.id === m.base)
              return (
                <CommandItem key={`m${m.local}`} value={`mod ${m.local} ${m.name}`} onSelect={() => onPick({ modItem: m.local })}
                  data-checked={isSel({ modItem: m.local })}>
                  <ItemIcon icon={base?.icon} />
                  <span className="flex-1 truncate">{m.name}</span>
                  <span className="text-xs text-muted-foreground">@item:{m.local}</span>
                </CommandItem>
              )
            })}
          </CommandGroup>
        )}
        {CAT_ORDER.map((cat) => {
          const list = game.filter((g) => g.cat === cat)
          if (!list.length) return null
          return (
            <CommandGroup key={cat} heading={`原版 · ${cat}`}>
              {list.map((g) => (
                <CommandItem key={g.id} value={`${g.id} ${g.name}`} onSelect={() => onPick({ item: g.id })} data-checked={isSel({ item: g.id })}>
                  <ItemIcon icon={g.icon} />
                  <span className="flex-1 truncate">{g.name}</span>
                  <span className="text-xs text-muted-foreground">{g.id} · {g.price} 文</span>
                </CommandItem>
              ))}
            </CommandGroup>
          )
        })}
      </CommandList>
    </Command>
  )
}

/** 积木里选物品的按钮 (弹出可搜索列表) */
export function ItemPicker({ p, value, onChange, mod = true, className = "" }: {
  p: Project; value: ItemRef; onChange: (r: ItemRef) => void; mod?: boolean; className?: string
}) {
  const game = useGameItems()
  const [open, setOpen] = useState(false)
  const d = describeRef(value, p, game)
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm" className={`h-8 justify-between gap-2 font-normal ${className}`}>
          <span className="flex min-w-0 items-center gap-2"><ItemIcon icon={d.icon} className="size-5" /><span className="truncate">{d.name}</span></span>
          <ChevronsUpDownIcon className="opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-80 p-0" align="start">
        <ItemList p={p} game={game} mod={mod} selected={value} onPick={(r) => { onChange(r); setOpen(false) }} />
      </PopoverContent>
    </Popover>
  )
}
