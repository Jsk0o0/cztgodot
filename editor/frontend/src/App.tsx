import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { OnFileDrop, OnFileDropOff } from "../wailsjs/runtime/runtime"
import { toast } from "sonner"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Spinner } from "@/components/ui/spinner"
import { Kbd } from "@/components/ui/kbd"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { Empty, EmptyContent, EmptyDescription, EmptyHeader, EmptyMedia, EmptyTitle } from "@/components/ui/empty"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { ResizableHandle, ResizablePanel, ResizablePanelGroup } from "@/components/ui/resizable"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { CircleAlertIcon, CircleCheckIcon, FolderOpenIcon, MousePointer2Icon, PackageIcon, PlayIcon, PlusIcon, SaveIcon, UserPlusIcon, XIcon, LockIcon, PencilIcon } from "lucide-react"
import { api, errText } from "@/lib/api"
import type { GameEvent, Issue, MapDetail, MapInfo, Model, NPC, Project, Selection, Snapshot, Status, StoryEvent } from "@/lib/types"
import { Viewport } from "@/components/editor/Viewport"
import { Sidebar } from "@/components/editor/Sidebar"
import { Inspector } from "@/components/editor/Inspector"
import { EventEditor } from "@/components/editor/EventEditor"
import { NewProjectDialog } from "@/components/editor/NewProjectDialog"
import { NewItemDialog } from "@/components/editor/ItemForm"
import { NewMonsterDialog } from "@/components/editor/MonsterForm"
import { NewBattleDialog } from "@/components/editor/BattleForm"
import { NewSkillDialog } from "@/components/editor/SkillForm"
import { OrigBrowser } from "@/components/editor/OrigBrowser"
import { EventViewer } from "@/components/editor/EventViewer"
import { OrigInfo } from "@/components/editor/OrigInfo"
import { CodeEditor } from "@/components/editor/CodeEditor"

const nextLocal = (xs: { local: number }[]) => xs.reduce((m, x) => Math.max(m, x.local), 0) + 1

function StartScreen({ status, onNew, onOpen, onFixRoot, opening }: { status: Status | null; onNew: () => void; onOpen: () => void; onFixRoot: () => void; opening: boolean }) {
  return (
    <div className="flex h-full items-center justify-center">
      <div className="w-[480px] space-y-4">
        {status && !status.dataOk && (
          <Alert variant="destructive">
            <CircleAlertIcon />
            <AlertTitle>没有找到游戏数据</AlertTitle>
            <AlertDescription>
              {status.error}
              <Button size="sm" variant="outline" className="mt-2" onClick={onFixRoot}><FolderOpenIcon />选择复刻工程目录</Button>
            </AlertDescription>
          </Alert>
        )}
        <Empty className="border">
          <EmptyHeader>
            <EmptyMedia variant="icon"><PackageIcon /></EmptyMedia>
            <EmptyTitle>苍之涛 · 工坊编辑器</EmptyTitle>
            <EmptyDescription>在原版地图上放 NPC、写对话和奖励，试玩后打包成 .pod 分享。</EmptyDescription>
          </EmptyHeader>
          <EmptyContent className="flex-row justify-center gap-2">
            {status === null ? (
              <><Spinner />正在检查游戏数据…</>
            ) : (
              <>
                <Button disabled={!status.dataOk} onClick={onNew}><PlusIcon />新建方案</Button>
                <Button variant="outline" disabled={!status.dataOk || opening} onClick={onOpen}>{opening ? <Spinner /> : <FolderOpenIcon />}打开方案</Button>
              </>
            )}
          </EmptyContent>
        </Empty>
      </div>
    </div>
  )
}

function IssuesDialog({ issues, open, onOpenChange }: { issues: Issue[]; open: boolean; onOpenChange: (v: boolean) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>校验结果</DialogTitle>
          <DialogDescription>有错误时不能试玩和打包；警告只是提醒。</DialogDescription>
        </DialogHeader>
        {issues.length === 0 ? (
          <p className="flex items-center gap-2 text-sm text-emerald-400"><CircleCheckIcon className="size-4" />没有发现问题</p>
        ) : (
          <ul className="max-h-80 space-y-2 overflow-auto text-sm">
            {issues.map((i, k) => (
              <li key={k} className="flex gap-2">
                <Badge variant={i.level === "error" ? "destructive" : "secondary"}>{i.level === "error" ? "错误" : "警告"}</Badge>
                <span className="text-muted-foreground">{i.where}</span>
                <span>{i.message}</span>
              </li>
            ))}
          </ul>
        )}
      </DialogContent>
    </Dialog>
  )
}

export default function App() {
  const [status, setStatus] = useState<Status | null>(null)
  const [project, setProject] = useState<Project | null>(null)
  const [dirty, setDirty] = useState(false)
  const [maps, setMaps] = useState<MapInfo[] | null>(null)
  const [models, setModels] = useState<Model[] | null>(null)
  const [mapId, setMapId] = useState<number | null>(null)
  const [detail, setDetail] = useState<MapDetail | null>(null)
  const [selection, setSelection] = useState<Selection>(null)
  const [eventLocal, setEventLocal] = useState<number | null>(null)
  const [tool, setTool] = useState<"select" | "place">("select")
  const [issues, setIssues] = useState<Issue[]>([])
  const [issuesOpen, setIssuesOpen] = useState(false)
  const [newItemOpen, setNewItemOpen] = useState(false)
  const [newMonsterOpen, setNewMonsterOpen] = useState(false)
  const [newBattleOpen, setNewBattleOpen] = useState(false)
  const [newSkillOpen, setNewSkillOpen] = useState(false)
  const [newOpen, setNewOpen] = useState(false)
  const [busy, setBusy] = useState<"" | "save" | "play" | "pack" | "open" | "import">("")
  const [importWarnings, setImportWarnings] = useState<Record<number, string[]>>({})
  const [confirmClose, setConfirmClose] = useState<null | (() => void)>(null)
  const [keyAsk, setKeyAsk] = useState(false)
  const [origEvent, setOrigEvent] = useState<StoryEvent | null>(null) // 原版浏览选中的事件 (只读)
  const [side, setSide] = useState<"mod" | "orig">("mod")
  const [snap, setSnap] = useState<Snapshot | null>(null) // 当前事件的剧情快照 (开始前那一刻在场的角色)
  const [snapIds, setSnapIds] = useState<Set<number>>(new Set()) // 有剧情快照的事件 (能播放预览)
  // 当前看的事件: 原版浏览选中的, 或方案里正在改的原版事件
  const activeEvent = !project || side === "orig" ? origEvent?.id ?? null : selection?.kind === "override" ? selection.id : null
  useEffect(() => {
    if (!status?.dataOk) return
    api.listChapters().then((chs) => setSnapIds(new Set(chs.flatMap((c) => c.events).filter((e) => e.reached).map((e) => e.id)))).catch(() => {})
  }, [status?.dataOk])
  useEffect(() => {
    if (activeEvent === null) { setSnap(null); return }
    let alive = true
    api.getSnapshot(activeEvent).then((sn) => {
      if (!alive) return
      setSnap(sn)
      if (sn) setMapId(sn.map)   // 事件开始时人在哪张图 (编号区间里写的地点可能不准)
    }).catch(() => alive && setSnap(null))
    return () => { alive = false }
  }, [activeEvent])

  const refreshStatus = useCallback(() => api.status().then(setStatus).catch((e) => toast.error(errText(e))), [])
  useEffect(() => { refreshStatus() }, [refreshStatus])
  // 开发服务器 (devserver.go) 截图用: ?open=1 自动打开 DEV_DIR 工程, ?select=npc:1 选中
  const dev = window as unknown as { __devAutoOpen?: boolean; __devSelect?: string }
  useEffect(() => {
    if (dev.__devAutoOpen && status?.dataOk && !project) open()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status])
  useEffect(() => {
    const s = dev.__devSelect
    // 开发用: ?select=种类:编号 (npc / event / item / quest / monster / battle / flag / model)
    const [kind, n, n2] = (s ?? "").split(":")
    if (project && kind === "orig_npc") {
      setMapId(Number(n))
      setSelection({ kind, map: Number(n), actor: Number(n2) })
    } else if (project && kind && n) {
      if (kind === "encounters") setMapId(Number(n))
      setSelection((kind === "encounters" ? { kind, map: Number(n) } : ["override", "member", "skill_edit"].includes(kind) ? { kind, id: Number(n) }
        : kind === "newgame" ? { kind } : { kind, local: Number(n) }) as Selection)
      if (kind === "event") setEventLocal(Number(n))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [project?.dir])

  // 开发用: ?select=orig:事件号 → 原版浏览选中这个事件
  useEffect(() => {
    const [kind, n] = (dev.__devSelect ?? "").split(":")
    if (kind !== "orig" || !status?.dataOk) return
    api.listChapters().then((chs) => {
      const e = chs.flatMap((c) => c.events).find((x) => x.id === Number(n))
      if (e) { setSide("orig"); pickOrig(e) }
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status?.dataOk, project?.dir])

  // 找到游戏数据后就读地图列表 (没打开方案也能浏览原版); 模型列表方案里放 NPC 才用
  useEffect(() => {
    if (!status?.dataOk) return
    if (maps === null) api.listMaps().then(setMaps).catch((e) => toast.error("读地图列表失败", { description: errText(e) }))
    if (project && models === null) api.listModels().then(setModels).catch((e) => toast.error("读模型列表失败", { description: errText(e) }))
  }, [project, status, maps, models])
  useEffect(() => {
    if (mapId === null) { setDetail(null); return }
    let alive = true
    api.getMap(mapId).then((d) => alive && setDetail(d)).catch((e) => toast.error("读地图失败", { description: errText(e) }))
    return () => { alive = false }
  }, [mapId])

  // 改动后自动重新校验 (防抖)
  useEffect(() => {
    if (!project) return
    const t = setTimeout(() => api.validate(project).then(setIssues).catch(() => {}), 300)
    return () => clearTimeout(t)
  }, [project])

  const update = (p: Project) => { setProject(p); setDirty(true) }
  const loaded = (p: Project) => {
    p = { ...p, models: p.models ?? [], npcs: p.npcs.map((n) => ({ ...n, model: n.model ?? 0 })) }
    setProject(p)
    setDirty(false)
    setSelection({ kind: "manifest" })
    setEventLocal(p.events[0]?.local ?? null)
    setMapId(p.npcs[0]?.map ?? 12201)
  }
  const guard = (fn: () => void) => (dirty ? setConfirmClose(() => fn) : fn())

  const save = useCallback(async () => {
    if (!project || busy) return
    setBusy("save")
    try {
      await api.saveProject(project)
      setDirty(false)
      toast.success("已保存")
    } catch (e) {
      toast.error("保存失败", { description: errText(e) })
    } finally {
      setBusy("")
    }
  }, [project, busy])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "s") { e.preventDefault(); save() }
      if (e.key === "Escape") setTool("select")
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [save])

  const open = async () => {
    const dir = await api.chooseDirectory("打开方案目录").catch(() => "")
    if (!dir) return
    setBusy("open")
    try {
      loaded(await api.openProject(dir))
      toast.success("已打开方案")
    } catch (e) {
      toast.error("打不开这个方案", { description: errText(e) })
    } finally {
      setBusy("")
    }
  }

  const play = async () => {
    if (!project || mapId === null) return
    const n = project.npcs.find((x) => selection?.kind === "npc" && x.local === selection.local) ?? project.npcs.find((x) => x.map === mapId)
    const pos: [number, number, number] = n ? [n.pos[0], n.pos[1], n.pos[2] + 120] : [0, 0, 0]
    setBusy("play")
    try {
      await api.playTest(project, n?.map ?? mapId, pos)
      setDirty(false)
      toast.success("已启动游戏", { description: "游戏窗口打开后会直接进入这张地图（已自动保存）。" })
    } catch (e) {
      toast.error("试玩失败", { description: errText(e) })
    } finally {
      setBusy("")
    }
  }

  const pack = async () => {
    if (!project) return
    setBusy("pack")
    try {
      const r = await api.packPod(project)
      setDirty(false)
      toast.success("打包完成", {
        description: `${r.path.split("/").pop()} · ${(r.size / 1024).toFixed(1)} KB · 签名指纹 ${r.fingerprint.slice(0, 8)}`,
        action: { label: "在访达中显示", onClick: () => api.reveal(r.path) },
      })
    } catch (e) {
      const msg = errText(e)
      if (msg === "NO_AUTHOR_KEY") setKeyAsk(true)
      else toast.error("打包失败", { description: msg })
    } finally {
      setBusy("")
    }
  }

  const createKey = async () => {
    try {
      await api.createAuthorKey()
      await refreshStatus()
      toast.success("已生成作者密钥", { description: "以后打包的 .pod 都用它签名，请备份 ~/.config/czt-pod/author.pem。" })
      pack()
    } catch (e) {
      toast.error("生成密钥失败", { description: errText(e) })
    }
  }

  // 导入一个 .glb (按钮选文件或拖进窗口); 用 ref 拿最新工程, 一次拖多个时依次导入
  const projectRef = useRef(project)
  projectRef.current = project
  const importFrom = async (src: string) => {
    const cur = projectRef.current
    if (!cur) return
    try {
      const r = await api.importModel(cur, src)
      const next = { ...cur, models: [...cur.models, r.model] }
      projectRef.current = next
      update(next)
      setImportWarnings((w) => ({ ...w, [r.model.local]: r.info.warnings }))
      setSelection({ kind: "model", local: r.model.local })
      if (r.info.warnings.length) toast.warning(`已导入「${r.model.name}」，有 ${r.info.warnings.length} 条提醒`, { description: r.info.warnings.join("；") })
      else toast.success(`已导入「${r.model.name}」`, { description: `${r.info.triangles} 面 · ${r.model.anims.length} 段动画` })
    } catch (e) {
      toast.error(`导入失败：${src.split("/").pop()}`, { description: errText(e) })
    }
  }
  // 给已有模型换文件 (编号不变, 用到它的 NPC 不用改)
  const replaceFrom = async (local: number, src: string) => {
    const cur = projectRef.current
    if (!cur) return
    try {
      const r = await api.replaceModel(cur, local, src)
      const next = { ...cur, models: cur.models.map((m) => (m.local === local ? r.model : m)) }
      projectRef.current = next
      update(next)
      setImportWarnings((w) => ({ ...w, [local]: r.info.warnings }))
      toast.success(`已给「${r.model.name}」换文件`, { description: `${r.info.triangles} 面 · ${r.model.anims.length} 段动画` })
    } catch (e) {
      toast.error(`换文件失败：${src.split("/").pop()}`, { description: errText(e) })
    }
  }
  const replaceModel = async (local: number) => {
    const src = await api.chooseGLB().catch(() => "")
    if (!src) return
    setBusy("import")
    await replaceFrom(local, src)
    setBusy("")
  }
  const selectionRef = useRef(selection)
  selectionRef.current = selection
  const importModel = async () => {
    if (!project) return
    const src = await api.chooseGLB().catch(() => "")
    if (!src) return
    setBusy("import")
    await importFrom(src)
    setBusy("")
  }
  // 拖文件进窗口
  const [dragging, setDragging] = useState(false)
  useEffect(() => {
    if (!project) return
    OnFileDrop(async (_x, _y, paths) => {
      setDragging(false)
      const glbs = paths.filter((p) => p.toLowerCase().endsWith(".glb"))
      if (glbs.length === 0) {
        toast.error("只能拖入 .glb 模型文件")
        return
      }
      setBusy("import")
      // 选中的是模型且只拖了一个文件 → 给这个模型换文件; 否则当新模型导入
      const sel = selectionRef.current
      if (sel?.kind === "model" && glbs.length === 1) await replaceFrom(sel.local, glbs[0])
      else for (const g of glbs) await importFrom(g)
      setBusy("")
    }, false)
    const enter = (e: DragEvent) => { if (e.dataTransfer?.types.includes("Files")) setDragging(true) }
    const leave = (e: DragEvent) => { if (!e.relatedTarget) setDragging(false) }
    const drop = () => setDragging(false)
    window.addEventListener("dragenter", enter)
    window.addEventListener("dragleave", leave)
    window.addEventListener("drop", drop)
    return () => {
      OnFileDropOff()
      window.removeEventListener("dragenter", enter)
      window.removeEventListener("dragleave", leave)
      window.removeEventListener("drop", drop)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [project?.dir])

  const placeNpc = async (g: [number, number, number]) => {
    if (!project || mapId === null) return
    const f = await api.floorAt(mapId, g[0], g[2], g[1]).catch(() => ({ y: g[1], ok: false }))
    const pos: NPC["pos"] = [Math.round(g[0]), Math.round(f.ok ? f.y : g[1]), Math.round(g[2])]
    if (selection?.kind === "orig_npc" && selection.map === mapId) {   // 挪原版 NPC: 记进方案的修改
      const others = project.npcEdits.filter((e) => !(e.map === mapId && e.actor === selection.actor))
      const ed = project.npcEdits.find((e) => e.map === mapId && e.actor === selection.actor) ?? { map: mapId, actor: selection.actor }
      update({ ...project, npcEdits: [...others, { ...ed, pos }] })
      setTool("select")
      toast(f.ok ? "已挪动并贴地" : "已挪动（这里找不到地面，用的是点到的高度）")
      return
    }
    const cur = selection?.kind === "npc" ? project.npcs.find((n) => n.local === selection.local && n.map === mapId) : undefined
    if (cur) {
      update({ ...project, npcs: project.npcs.map((n) => (n.local === cur.local ? { ...n, pos } : n)) })
      toast(f.ok ? "已移动并贴地" : "已移动（这里找不到地面，用的是点到的高度）")
    } else {
      const local = nextLocal(project.npcs)
      const n: NPC = { local, map: mapId, name: `新 NPC ${local}`, act: 114, model: 0, pose: 0, pos, facing: 0, talk: true, event: 0 }
      update({ ...project, npcs: [...project.npcs, n] })
      setSelection({ kind: "npc", local })
      toast.success(`已放置「${n.name}」`, { description: "在右边设置名字、模型和对话事件。" })
    }
    setTool("select")
  }

  const counts = useMemo(() => ({ err: issues.filter((i) => i.level === "error").length, warn: issues.filter((i) => i.level === "warning").length }), [issues])
  const ev = project?.events.find((e) => e.local === eventLocal) ?? null

  const pickOrig = (e: StoryEvent) => { setOrigEvent(e); if (e.mid) setMapId(e.mid) }
  // 播放预览: 从剧情快照启动游戏播这个事件 (打开了方案就连方案一起, 看改过的效果)
  const playPreview = (id: number) =>
    api.playEvent(id, project).then(() => toast.success(`正在游戏里播放事件 #${id}`, { description: project ? "已加载当前方案（会先保存）。" : "原版效果。" }))
      .catch((e) => toast.error("播放不了", { description: errText(e) }))
  const playButton = (id: number) => (
    <Button size="sm" variant="outline" disabled={!(snapIds.has(id) || (snap?.event === id)) || !status?.godotOk} onClick={() => playPreview(id)}
      title={snapIds.has(id) ? "从这段剧情开始前的那一刻在游戏里播放" : snap?.event === id ? `借用事件 #${snap.borrowed} 的快照（同一张地图）在游戏里播放` : "这张地图还没有剧情快照"}><PlayIcon />播放预览</Button>
  )
  const origBrowser = <OrigBrowser maps={maps} mapId={mapId} eventId={origEvent?.id ?? null} onMap={(id) => setMapId(id)} onEvent={pickOrig} />
  const viewport = (
    <div className="relative h-full">
      {mapId === null ? (
        <Empty className="h-full"><EmptyHeader><EmptyTitle>选择一张地图</EmptyTitle><EmptyDescription>在左边选一个剧情事件或一张地图。</EmptyDescription></EmptyHeader></Empty>
      ) : (
        <Viewport detail={detail} npcs={project ? project.npcs.filter((n) => n.map === mapId) : []} models={project?.models ?? []}
          selected={selection?.kind === "npc" ? selection.local : null} placing={!!project && tool === "place"} showZones={selection?.kind === "encounters"}
          edits={project?.npcEdits.filter((e) => e.map === mapId) ?? []} selectedOrig={selection?.kind === "orig_npc" ? selection.actor : null}
          onPickOrig={project && side === "mod" ? (actor) => setSelection({ kind: "orig_npc", map: mapId, actor }) : undefined}
          cast={snap && activeEvent === snap.event && snap.map === mapId ? snap.cast : null}
          snapCam={snap && activeEvent === snap.event && snap.map === mapId ? snap.cam : null}
          onPlace={placeNpc} onSelect={(l) => project && (l === null ? setSelection(null) : setSelection({ kind: "npc", local: l }))} />
      )}
      {project && mapId !== null && side === "mod" && (
        <div className="absolute top-3 left-3 flex items-center gap-2 rounded-lg border bg-card/90 p-1 backdrop-blur">
          <ToggleGroup type="single" value={tool} onValueChange={(v) => v && setTool(v as typeof tool)} size="sm">
            <ToggleGroupItem value="select" aria-label="选择"><MousePointer2Icon />选择</ToggleGroupItem>
            <ToggleGroupItem value="place" aria-label="放置 NPC"><UserPlusIcon />{selection?.kind === "npc" || selection?.kind === "orig_npc" ? "移动 NPC" : "放置 NPC"}</ToggleGroupItem>
          </ToggleGroup>
          {tool === "place" && <span className="pr-2 text-xs text-muted-foreground">点地面{selection?.kind === "npc" || selection?.kind === "orig_npc" ? "移动选中的 NPC" : "放一个新 NPC"} · <Kbd>Esc</Kbd> 取消</span>}
        </div>
      )}
      {detail && (
        <div className="absolute top-3 right-3 rounded-md border bg-card/90 px-2 py-1 text-xs text-muted-foreground backdrop-blur">
          {detail.title || detail.name} · {detail.id} · 左键旋转 右键平移 滚轮缩放
        </div>
      )}
      {detail && activeEvent !== null && (
        <div className="absolute bottom-3 left-3 rounded-md border bg-card/90 px-2 py-1 text-xs backdrop-blur">
          {snap && snap.event === activeEvent && snap.borrowed
            ? <span className="text-sky-300">事件 #{activeEvent} 自动通关没触发到：借用同一张地图上事件 #{snap.borrowed} 开始前的现场（{snap.cast?.length ?? 0} 个角色）</span>
            : snap && snap.event === activeEvent
            ? <span className="text-emerald-300">按剧情显示：事件 #{activeEvent} 开始前在场的 {snap.cast?.length ?? 0} 个角色</span>
            : <span className="text-amber-300">事件 #{activeEvent} 所在的地图还没有剧情快照：人物按地图静态数据显示，没按剧情筛选</span>}
        </div>
      )}
    </div>
  )

  // 没打开方案: 原版只读浏览 (剧情线路、地图、事件指令)
  if (!project) {
    if (!status?.dataOk) {
      return (
        <div className="h-screen bg-background">
          <StartScreen status={status} onNew={() => setNewOpen(true)} onOpen={open} opening={busy === "open"}
            onFixRoot={() => api.chooseGameRoot().then((d) => d && refreshStatus()).catch((e) => toast.error(errText(e)))} />
        </div>
      )
    }
    return (
      <div className="grid h-screen grid-rows-[48px_1fr] bg-background text-foreground">
        <header className="flex items-center gap-2 border-b bg-card px-3" style={{ ["--wails-draggable" as string]: "drag" }}>
          <span className="pl-16 font-semibold tracking-wider text-primary">苍之涛 · 工坊编辑器</span>
          <Badge variant="outline" className="gap-1 font-normal"><LockIcon className="size-3" />原版 · 只读</Badge>
          <div className="flex-1" />
          <span className="text-xs text-muted-foreground">要修改原版内容，先新建一个方案</span>
          <Button size="sm" onClick={() => setNewOpen(true)}><PlusIcon />新建方案</Button>
          <Button size="sm" variant="outline" disabled={busy === "open"} onClick={open}>{busy === "open" ? <Spinner /> : <FolderOpenIcon />}打开方案</Button>
        </header>
        <ResizablePanelGroup orientation="horizontal">
          <ResizablePanel defaultSize="22" minSize={240}>{origBrowser}</ResizablePanel>
          <ResizableHandle />
          <ResizablePanel defaultSize="58" minSize={400}>
            <ResizablePanelGroup orientation="vertical">
              <ResizablePanel defaultSize="50" minSize={200}>{viewport}</ResizablePanel>
              <ResizableHandle />
              <ResizablePanel defaultSize="50" minSize={160}><EventViewer id={origEvent?.id ?? null} maps={maps} action={(info) => playButton(info.id)} /></ResizablePanel>
            </ResizablePanelGroup>
          </ResizablePanel>
          <ResizableHandle />
          <ResizablePanel defaultSize="20" minSize={240}><OrigInfo e={origEvent} hasProject={false} snapMap={snap && snap.event === origEvent?.id ? (maps?.find((m) => m.id === snap.map)?.title ?? String(snap.map)) : null} /></ResizablePanel>
        </ResizablePanelGroup>
        <NewProjectDialog open={newOpen} onOpenChange={setNewOpen} onCreated={(p) => { loaded(p); toast.success("方案已创建") }} />
      </div>
    )
  }

  return (
    <div className="grid h-screen grid-rows-[48px_1fr_28px] bg-background text-foreground">
      {/* 工具栏 */}
      <header className="flex items-center gap-2 border-b bg-card px-3" style={{ ["--wails-draggable" as string]: "drag" }}>
        <span className="pl-16 font-semibold tracking-wider text-primary">苍之涛 · 工坊编辑器</span>
        <Badge variant="outline" className="font-normal">{project.manifest.name || "未命名"} · {project.manifest.id} · v{project.manifest.version}{dirty ? " · 未保存" : ""}</Badge>
        <div className="flex-1" />
        <Button variant="ghost" size="sm" onClick={() => setIssuesOpen(true)}>
          {counts.err > 0 ? <CircleAlertIcon className="text-destructive" /> : <CircleCheckIcon className="text-emerald-400" />}
          {counts.err > 0 ? `${counts.err} 个错误` : "校验通过"}{counts.warn > 0 && ` · ${counts.warn} 个警告`}
        </Button>
        <Tooltip>
          <TooltipTrigger asChild>
            <Button variant="outline" size="sm" disabled={!!busy || !dirty} onClick={save}>{busy === "save" ? <Spinner /> : <SaveIcon />}保存</Button>
          </TooltipTrigger>
          <TooltipContent>保存 <Kbd>⌘S</Kbd></TooltipContent>
        </Tooltip>
        <Button size="sm" className="bg-emerald-700 text-white hover:bg-emerald-600" disabled={!!busy || counts.err > 0 || !status?.godotOk} onClick={play}>
          {busy === "play" ? <Spinner /> : <PlayIcon />}试玩
        </Button>
        <Button size="sm" variant="outline" disabled={!!busy || counts.err > 0} onClick={pack}>{busy === "pack" ? <Spinner /> : <PackageIcon />}打包 .pod</Button>
        <Tooltip>
          <TooltipTrigger asChild>
            <Button variant="ghost" size="icon-sm" aria-label="关闭方案" onClick={() => guard(() => { setProject(null); setMaps(null); setMapId(null) })}><XIcon /></Button>
          </TooltipTrigger>
          <TooltipContent>关闭方案</TooltipContent>
        </Tooltip>
      </header>

      <ResizablePanelGroup orientation="horizontal">
        <ResizablePanel defaultSize="18" minSize={220}>
          <div className="flex h-full flex-col bg-sidebar">
          <ToggleGroup type="single" value={side} onValueChange={(v) => v && setSide(v as typeof side)} variant="outline" size="sm" className="m-2 w-[calc(100%-1rem)]">
            <ToggleGroupItem value="mod" className="flex-1">方案</ToggleGroupItem>
            <ToggleGroupItem value="orig" className="flex-1"><LockIcon />原版</ToggleGroupItem>
          </ToggleGroup>
          <div className="min-h-0 flex-1">
          {side === "orig" ? origBrowser : <Sidebar project={project} maps={maps} mapId={mapId} selection={selection}
            onMap={(id) => { setMapId(id); setTool("select") }}
            onSelect={(s) => { setSelection(s); if (s?.kind === "event") setEventLocal(s.local) }}
            onAddEvent={() => { const local = nextLocal(project.events); update({ ...project, events: [...project.events, { local, name: `事件 ${local}`, blocks: [] }] }); setEventLocal(local); setSelection({ kind: "event", local }) }}
            onAddFlag={() => { const local = nextLocal(project.flags); update({ ...project, flags: [...project.flags, { local, name: `旗标 ${local}` }] }); setSelection({ kind: "flag", local }) }}
            onAddItem={() => setNewItemOpen(true)}
            onAddMonster={() => setNewMonsterOpen(true)}
            onAddBattle={() => setNewBattleOpen(true)}
            onAddSkill={() => setNewSkillOpen(true)}
            onAddVar={() => { const local = nextLocal(project.vars); update({ ...project, vars: [...project.vars, { local, name: `变量 ${local}` }] }); setSelection({ kind: "var", local }) }}
            onAddQuest={() => {
              const local = nextLocal(project.quests)
              if (local > 49) { toast.error("一个 mod 最多 49 个任务"); return }
              update({ ...project, quests: [...project.quests, { local, title: `任务 ${local}`, main: false }] })
              setSelection({ kind: "quest", local })
            }}
            onImportModel={importModel} importing={busy === "import"} /> }
          </div>
          </div>
        </ResizablePanel>
        <ResizableHandle />
        <ResizablePanel defaultSize="60" minSize={400}>
          <ResizablePanelGroup orientation="vertical">
            <ResizablePanel defaultSize="62" minSize={200}>
              {viewport}
            </ResizablePanel>
            <ResizableHandle />
            <ResizablePanel defaultSize="38" minSize={160}>
              {side === "orig" ? (
                <EventViewer id={origEvent?.id ?? null} maps={maps} action={(info) => {
                  const has = project.overrides.some((o) => o.id === info.id)
                  return (<>{playButton(info.id)}
                    <Button size="sm" variant={has ? "outline" : "default"} onClick={() => {
                      if (!has) {
                        const name = origEvent?.name || origEvent?.trig || origEvent?.map || ""
                        update({ ...project, overrides: [...project.overrides, { id: info.id, name, code: JSON.parse(JSON.stringify(info.code ?? [])) }] })
                        toast.success(`已把原版事件 #${info.id} 复制到方案`, { description: "在下面逐条修改；原版本身不会变。" })
                      }
                      setSide("mod")
                      setSelection({ kind: "override", id: info.id })
                    }}><PencilIcon />{has ? "在方案里打开" : "复制到方案修改"}</Button></>
                  )
                }} />
              ) : selection?.kind === "override" && project.overrides.some((o) => o.id === selection.id) ? (
                <CodeEditor ov={project.overrides.find((o) => o.id === selection.id)!} p={project} maps={maps} action={playButton(selection.id)}
                  onChange={(no) => update({ ...project, overrides: project.overrides.map((o) => (o.id === no.id ? no : o)) })} />
              ) : (
                <EventEditor project={project} event={ev}
                  onChange={(ne: GameEvent) => update({ ...project, events: project.events.map((e) => (e.local === ne.local ? ne : e)) })} />
              )}
            </ResizablePanel>
          </ResizablePanelGroup>
        </ResizablePanel>
        <ResizableHandle />
        <ResizablePanel defaultSize="22" minSize={260}>
          {side === "orig" ? <OrigInfo e={origEvent} hasProject snapMap={snap && snap.event === origEvent?.id ? (maps?.find((m) => m.id === snap.map)?.title ?? String(snap.map)) : null} /> : <Inspector project={project} selection={selection} models={models} onProject={update}
            onDeleteNpc={(l) => { update({ ...project, npcs: project.npcs.filter((n) => n.local !== l) }); setSelection(null); toast("已删除 NPC") }}
            onDeleteQuest={(l) => { update({ ...project, quests: project.quests.filter((x) => x.local !== l) }); setSelection(null); toast("已删除任务") }}
            onDeleteItem={(l) => { update({ ...project, items: project.items.filter((x) => x.local !== l) }); setSelection(null); toast("已删除物品") }}
            onDeleteMonster={(l) => { update({ ...project, monsters: project.monsters.filter((x) => x.local !== l) }); setSelection(null); toast("已删除怪物") }}
            onDeleteVar={(l) => { update({ ...project, vars: project.vars.filter((x) => x.local !== l) }); setSelection(null); toast("已删除变量") }}
            detail={detail}
            onDeleteBattle={(l) => { update({ ...project, battles: project.battles.filter((x) => x.local !== l) }); setSelection(null); toast("已删除战斗") }}
            onDeleteFlag={(l) => { update({ ...project, flags: project.flags.filter((f) => f.local !== l) }); setSelection(null); toast("已删除旗标") }}
            onDeleteModel={(l) => { update({ ...project, models: project.models.filter((m) => m.local !== l) }); setSelection(null); toast("已删除模型", { description: "保存方案时会一起删掉 models/ 里的文件。" }) }}
            onReplaceModel={replaceModel} busy={busy === "import"}
            importWarnings={importWarnings} />}
        </ResizablePanel>
      </ResizablePanelGroup>

      <footer className="flex items-center gap-4 border-t bg-card px-3 text-xs text-muted-foreground">
        <span className={status?.dataOk ? "text-emerald-400" : "text-destructive"}>● {status?.dataOk ? "已找到游戏数据" : "没有游戏数据"}</span>
        <span className="truncate">方案：{project.dir}</span>
        <div className="flex-1" />
        <span>{status?.godotOk ? "Godot 已就绪" : "找不到 Godot，无法试玩"}</span>
        <span>{status?.authorKey ? "作者密钥已就绪" : "还没有作者密钥（第一次打包时生成）"}</span>
      </footer>

      {dragging && (
        <div className="pointer-events-none fixed inset-3 z-50 flex items-center justify-center rounded-xl border-2 border-dashed border-primary bg-background/70 text-lg text-primary backdrop-blur-sm">
          {selection?.kind === "model"
            ? `松开给「${project?.models.find((m) => m.local === selection.local)?.name ?? "模型"}」换文件（拖多个则当新模型导入）`
            : "松开导入模型（.glb）"}
        </div>
      )}
      <IssuesDialog issues={issues} open={issuesOpen} onOpenChange={setIssuesOpen} />
      <NewItemDialog open={newItemOpen} onOpenChange={setNewItemOpen} p={project}
        onCreate={(g) => {
          const local = nextLocal(project.items)
          const heal = g.sub === 202
          update({ ...project, items: [...project.items, { local, base: g.id, name: `${g.name}（改）`, desc: g.desc, price: g.price,
            ...(heal ? { fx1: [...(g.fx1 ?? [0, 0, 0, 0, 0, 0])], fx2: [...(g.fx2 ?? [0, 0, 0, 0, 0, 0, 0])] } : {}) }] })
          setSelection({ kind: "item", local })
          toast.success(`已复制「${g.name}」`, { description: "在右边改名字、说明、价格和效果。" })
        }} />
      <NewMonsterDialog open={newMonsterOpen} onOpenChange={setNewMonsterOpen} p={project}
        onCreate={(g) => {
          const local = nextLocal(project.monsters)
          if (local > 255) { toast.error("一个 mod 最多 255 只怪物"); return }
          const { level, hp, mp, sp, atk, def, spd, matk, mdef, hit, eva, mhit, meva } = g
          update({ ...project, monsters: [...project.monsters, { local, base: g.id, name: `${g.name}（改）`, desc: g.desc,
            level, hp, mp, sp, atk, def, spd, matk, mdef, hit, eva, mhit, meva, exp: g.exp, money: g.money,
            dropRate: g.drop[1] ? g.drop[0] : 0, dropItem: g.drop[1] || undefined }] })
          setSelection({ kind: "monster", local })
          toast.success(`已复制「${g.name}」`, { description: "在右边改名字、数值和掉落。" })
        }} />
      <NewBattleDialog open={newBattleOpen} onOpenChange={setNewBattleOpen}
        onCreate={(bf) => {
          const local = nextLocal(project.battles)
          if (local > 63) { toast.error("一个 mod 最多 63 场战斗"); return }
          update({ ...project, battles: [...project.battles, { local, name: `战斗 ${local}`, base: bf.id, enemies: bf.slots.map((s, i) => ({ at: i, monster: s.monster })) }] })
          setSelection({ kind: "battle", local })
          toast.success(`已复制战场「${bf.name.replace(/_\d+$/, "")}」`, { description: "在右边把敌人换成自己的怪物。" })
        }} />
      <NewSkillDialog open={newSkillOpen} onOpenChange={setNewSkillOpen} p={project}
        onCopy={(g) => {
          const local = nextLocal(project.skills)
          if (local > 255) { toast.error("一个方案最多 255 个新技能"); return }
          update({ ...project, skills: [...project.skills, { local, base: g.id, name: `${g.name}（改）`, desc: g.desc, power: g.power, cost: { ...(g.cost ?? {}) } }] })
          setSelection({ kind: "skill", local })
          toast.success(`已复制「${g.name}」`, { description: "改好后在队员的成长表或开局里让人学会它。" })
        }}
        onEditOrig={(g) => {
          if (!project.skillEdits.some((x) => x.id === g.id)) update({ ...project, skillEdits: [...project.skillEdits, { id: g.id }] })
          setSelection({ kind: "skill_edit", id: g.id })
        }} />
      <AlertDialog open={confirmClose !== null} onOpenChange={(v) => !v && setConfirmClose(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>有没保存的改动</AlertDialogTitle>
            <AlertDialogDescription>不保存就关闭方案，这些改动会丢失。</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>取消</AlertDialogCancel>
            <AlertDialogAction variant="destructive" onClick={() => { confirmClose?.(); setConfirmClose(null) }}>不保存，关闭</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <AlertDialog open={keyAsk} onOpenChange={setKeyAsk}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>需要作者密钥</AlertDialogTitle>
            <AlertDialogDescription>打包的 .pod 要用你的作者密钥签名，游戏靠它确认文件没被别人改过。现在生成一个吗？（存在 ~/.config/czt-pod/author.pem，请妥善备份）</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>以后再说</AlertDialogCancel>
            <AlertDialogAction onClick={createKey}>生成并打包</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
