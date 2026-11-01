import { useEffect, useRef, useState } from "react"
import * as THREE from "three"
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js"
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js"
import { clone as cloneSkinned } from "three/examples/jsm/utils/SkeletonUtils.js"
import type { GLTF } from "three/examples/jsm/loaders/GLTFLoader.js"
import { Spinner } from "@/components/ui/spinner"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { TriangleAlertIcon } from "lucide-react"
import type { CastMember, NpcEdit, CustomModel, MapDetail, NPC } from "@/lib/types"

// 自定义模型: 每个文件只读一次, NPC 各自克隆 (带骨骼的要用 SkeletonUtils.clone)
const glbCache = new Map<string, Promise<GLTF>>()
function loadGLB(url: string) {
  let p = glbCache.get(url)
  if (!p) {
    p = new GLTFLoader().loadAsync(url)
    p.catch(() => glbCache.delete(url))
    glbCache.set(url, p)
  }
  return p
}

// 坐标: 场景 GLB 局部坐标 = (游戏坐标 + offset) × 0.01; 原版是左手系, 游戏画面水平翻转显示 →
// 这里把整个场景放进 scale.x = −1 的 root, 看到的左右和游戏里一致
const S = 0.01
// 原版角色模型的正面是局部 −Z (游戏 field_actor.set_facing 的注释), 自定义 glb 按 glTF 惯例是 +Z
// (游戏 mod_manager.instantiate_model 给它转 180°)。这里的摆法按自定义模型写的, 原版的再转 180°
const ORIG_YAW = Math.PI

type Props = {
  detail: MapDetail | null
  npcs: NPC[]
  models: CustomModel[]
  selected: number | null
  placing: boolean
  onPlace: (game: [number, number, number]) => void
  onSelect: (local: number | null) => void
  showZones?: boolean // 画出原版遇敌区域 (编辑遇敌时)
  edits?: NpcEdit[] // 方案对这张图原版 NPC 的修改 (挪位置 / 改名 / 删掉)
  selectedOrig?: number | null
  cast?: CastMember[] | null
  snapCam?: { ang: [number, number, number]; d: number; k: number } | null // 快照里游戏当时的镜头 // 剧情快照里那一刻在场的角色 (有就按它画模型; 没有就画地图静态 NPC 的标记)
  onPickOrig?: (actor: number) => void // 点到原版 NPC (方案模式)
}

/** 场景的包围盒, 不算远景天空 (场景 GLB 里 *_backdrop 网格, 比地图大得多) */
function sceneBox(root: THREE.Object3D): THREE.Box3 {
  const box = new THREE.Box3()
  root.updateMatrixWorld(true)
  root.traverse((o) => {
    const m = o as THREE.Mesh
    if (!m.isMesh) return
    for (let p: THREE.Object3D | null = m; p; p = p.parent) if (p.name.endsWith("_backdrop")) return
    box.union(new THREE.Box3().setFromObject(m))
  })
  return box.isEmpty() ? new THREE.Box3().setFromObject(root) : box
}

function label(text: string, color: string): THREE.Sprite {
  const c = document.createElement("canvas")
  const ctx = c.getContext("2d")!
  ctx.font = "600 26px PingFang SC, sans-serif"
  const w = Math.ceil(ctx.measureText(text).width) + 20
  c.width = w
  c.height = 40
  ctx.font = "600 26px PingFang SC, sans-serif"
  ctx.fillStyle = "rgba(20,16,12,0.72)"
  ctx.beginPath()
  ctx.roundRect(0, 0, w, 40, 8)
  ctx.fill()
  ctx.fillStyle = color
  ctx.fillText(text, 10, 29)
  const tex = new THREE.CanvasTexture(c)
  tex.colorSpace = THREE.SRGBColorSpace
  // 固定屏幕大小 (不随远近缩放): 整张大地图和推近看现场时名字都一样大, 不会挡住模型
  const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false, transparent: true, sizeAttenuation: false }))
  sp.scale.set((w / 40) * 0.034, 0.034, 1)
  sp.renderOrder = 10
  return sp
}

/** 游戏里的 unshaded 画法: 换成不受光照的材质, 加法层 (*_add) 用加法混合 */
function unshade(obj: THREE.Object3D) {
  obj.traverse((o) => {
    const m = o as THREE.Mesh
    if (!m.isMesh) return
    const mats = Array.isArray(m.material) ? m.material : [m.material]
    const out = mats.map((mat) => {
      const src = mat as THREE.MeshStandardMaterial
      const add = src.name?.endsWith("_add")
      return new THREE.MeshBasicMaterial({
        map: src.map ?? null,
        color: src.color ?? new THREE.Color(1, 1, 1),
        transparent: add || src.transparent,
        alphaTest: src.alphaTest,
        side: THREE.DoubleSide,
        vertexColors: add,
        blending: add ? THREE.AdditiveBlending : THREE.NormalBlending,
        depthWrite: !add,
      })
    })
    m.material = Array.isArray(m.material) ? out : out[0]
  })
}

export function Viewport({ detail, npcs, models, selected, placing, onPlace, onSelect, showZones = false, edits = [], selectedOrig = null, onPickOrig, cast = null, snapCam = null }: Props) {
  const host = useRef<HTMLDivElement>(null)
  const three = useRef<{
    renderer: THREE.WebGLRenderer
    camera: THREE.PerspectiveCamera
    controls: OrbitControls
    root: THREE.Group
    scene: THREE.Group
    marks: THREE.Group
    mod: THREE.Group
    zones: THREE.Group
    mixers: THREE.AnimationMixer[]
    castMixers: THREE.AnimationMixer[]
  } | null>(null)
  const [loading, setLoading] = useState(false)
  const [k, setK] = useState(1) // 标记缩放: 按场景大小 (大地图上标记也看得清)
  const [error, setError] = useState("")
  const cb = useRef<{ onPlace: Props["onPlace"]; onSelect: Props["onSelect"]; placing: boolean; detail: MapDetail | null; onPickOrig?: Props["onPickOrig"] }>({ onPlace, onSelect, placing, detail, onPickOrig })
  cb.current = { onPlace, onSelect, placing, detail, onPickOrig }

  // 初始化 three.js
  useEffect(() => {
    const el = host.current!
    const renderer = new THREE.WebGLRenderer({ antialias: true })
    renderer.setPixelRatio(window.devicePixelRatio)
    renderer.outputColorSpace = THREE.SRGBColorSpace
    el.appendChild(renderer.domElement)
    const world = new THREE.Scene()
    world.background = new THREE.Color(0x2a2520)
    const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 2000)
    camera.position.set(0, 30, 30)
    const controls = new OrbitControls(camera, renderer.domElement)
    controls.enableDamping = true
    controls.mouseButtons = { LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.PAN }
    const root = new THREE.Group()
    root.scale.x = -1
    world.add(root)
    const scene = new THREE.Group()
    const marks = new THREE.Group()
    const mod = new THREE.Group()
    const zones = new THREE.Group()
    root.add(scene, marks, mod, zones)
    const mixers: THREE.AnimationMixer[] = []
    const castMixers: THREE.AnimationMixer[] = []
    three.current = { renderer, camera, controls, root, scene, marks, mod, zones, mixers, castMixers }
    const clock = new THREE.Clock()

    const fit = () => {
      const r = el.getBoundingClientRect()
      renderer.setSize(r.width, r.height)
      camera.aspect = r.width / Math.max(1, r.height)
      camera.updateProjectionMatrix()
    }
    const ro = new ResizeObserver(fit)
    ro.observe(el)
    fit()
    let raf = 0
    // 录演示视频用 (只在 ?demo 时挂出): 游戏坐标 → 屏幕坐标, 镜头平滑推到某点
    let fly: { t0: number; dur: number; p0: THREE.Vector3; p1: THREE.Vector3; q0: THREE.Vector3; q1: THREE.Vector3 } | null = null
    if (location.search.includes("demo")) {
      const toWorld = (g: number[]) => {
        const d = cb.current.detail!
        return root.localToWorld(new THREE.Vector3((g[0] + d.offset[0]) * S, (g[1] + d.offset[1]) * S, (g[2] + d.offset[2]) * S))
      }
      ;(window as unknown as Record<string, unknown>).__vp = {
        screenOf: (g: number[]) => {
          const v = toWorld(g).project(camera)
          const r = renderer.domElement.getBoundingClientRect()
          return { x: r.left + ((v.x + 1) / 2) * r.width, y: r.top + ((1 - v.y) / 2) * r.height }
        },
        flyTo: (g: number[], off: number[], dur: number) => {
          const q1 = toWorld(g)
          fly = { t0: performance.now(), dur: dur * 1000, p0: camera.position.clone(), q0: controls.target.clone(), q1,
            p1: q1.clone().add(new THREE.Vector3(off[0], off[1], off[2])) }
        },
      }
    }
    const tick = () => {
      if (fly) {
        const t = Math.min(1, (performance.now() - fly.t0) / fly.dur)
        const e = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2
        camera.position.lerpVectors(fly.p0, fly.p1, e)
        controls.target.lerpVectors(fly.q0, fly.q1, e)
        if (t >= 1) fly = null
      }
      controls.update()
      const dt = clock.getDelta()
      for (const m of mixers) m.update(dt)
      for (const m of castMixers) m.update(dt)
      renderer.render(world, camera)
      raf = requestAnimationFrame(tick)
    }
    tick()

    // 点击 (不是拖动): 先看是否点到本 mod 的 NPC, 否则放置模式下取场景表面的点
    let down: { x: number; y: number } | null = null
    const ray = new THREE.Raycaster()
    const ndc = (e: PointerEvent) => {
      const r = renderer.domElement.getBoundingClientRect()
      return new THREE.Vector2(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1)
    }
    const onDown = (e: PointerEvent) => (down = e.button === 0 ? { x: e.clientX, y: e.clientY } : null)
    const onUp = (e: PointerEvent) => {
      if (!down || Math.hypot(e.clientX - down.x, e.clientY - down.y) > 4) return
      down = null
      ray.setFromCamera(ndc(e), camera)
      const hitMod = ray.intersectObjects(mod.children, true)[0]
      // 原版 NPC 标记 (方案模式可以点选修改); 放置模式下点地面优先
      const hitOrig = !cb.current.placing && cb.current.onPickOrig ? ray.intersectObjects(marks.children, true).find((h) => h.object.userData.actor !== undefined) : undefined
      if (hitOrig && !hitMod) {
        cb.current.onPickOrig!(hitOrig.object.userData.actor as number)
        return
      }
      if (hitMod) {
        let o: THREE.Object3D | null = hitMod.object
        while (o && o.userData.local === undefined) o = o.parent
        if (o) {
          cb.current.onSelect(o.userData.local as number)
          return
        }
      }
      const d = cb.current.detail
      if (!cb.current.placing || !d) {
        cb.current.onSelect(null)
        return
      }
      const hit = ray.intersectObjects(scene.children, true)[0]
      if (!hit) return
      const p = root.worldToLocal(hit.point.clone())
      cb.current.onPlace([p.x / S - d.offset[0], p.y / S - d.offset[1], p.z / S - d.offset[2]])
    }
    renderer.domElement.addEventListener("pointerdown", onDown)
    renderer.domElement.addEventListener("pointerup", onUp)
    return () => {
      cancelAnimationFrame(raf)
      ro.disconnect()
      controls.dispose()
      renderer.dispose()
      el.removeChild(renderer.domElement)
      three.current = null
    }
  }, [])

  // 换地图: 读场景 GLB + 原版 NPC 标记
  useEffect(() => {
    const t = three.current
    if (!t) return
    t.scene.clear()
    t.marks.clear()
    setError("")
    if (!detail) return
    let cancelled = false
    setLoading(true)
    new GLTFLoader()
      .loadAsync(`/gamedata/${detail.scene}`)
      .then((g) => {
        if (cancelled) return
        unshade(g.scene)
        // 远景天空 (*_backdrop) 编辑时用不到, 还会把地形罩住 (镜头在球里时只看得到球面)
        g.scene.traverse((o) => { if (o.name.endsWith("_backdrop")) o.visible = false })
        t.scene.add(g.scene)
        // 镜头: 对准场景中心, 斜上方 45°
        const box = sceneBox(g.scene)
        const c = box.getCenter(new THREE.Vector3())
        const r = box.getSize(new THREE.Vector3()).length() * 0.45
        const kk = Math.max(1, r / 25)
        setK(kk)
        t.controls.target.copy(c)
        t.camera.position.copy(c).add(new THREE.Vector3(0, r * 0.75, r * 0.75))
        t.camera.far = r * 20
        t.camera.updateProjectionMatrix()
      })
      .catch((e) => !cancelled && setError(String(e?.message ?? e)))
      .finally(() => !cancelled && setLoading(false))
    return () => {
      cancelled = true
    }
  }, [detail])

  // 原版角色: 有剧情快照就画那一刻在场的角色 (原版模型 + 当时的动作), 没有就画地图静态 NPC 的标记 (蓝点)。
  // 方案改过的按改后的位置 / 名字画, 删掉的画成半透明红点; 选中的加亮
  useEffect(() => {
    const t = three.current
    if (!t) return
    t.marks.clear()
    t.castMixers.length = 0
    if (!detail || loading) return
    let stale = false
    const toLocal = (p: number[]) => new THREE.Vector3((p[0] + detail.offset[0]) * S, (p[1] + detail.offset[1]) * S, (p[2] + detail.offset[2]) * S)
    const list: { actor: number; name: string; pos: number[]; facing: number; glb?: string; pose?: number; scale?: number; player?: boolean }[] =
      cast ? cast.map((c) => ({ actor: c.actor, name: c.name, pos: c.pos, facing: c.facing, glb: c.glb, pose: c.pose, scale: c.scale, player: c.player }))
        : (detail.npcs ?? []).map((n) => ({ actor: n.actor, name: n.name, pos: n.pos, facing: n.facing }))
    for (const n of list) {
      const ed = edits.find((e) => e.actor === n.actor)
      const sel = selectedOrig === n.actor
      const g = new THREE.Group()
      g.position.copy(toLocal(ed?.pos ?? n.pos))
      t.marks.add(g)
      const color = ed?.remove ? 0xd05050 : sel ? 0xffd27a : ed ? 0x9ad0ff : n.player ? 0xf0a050 : 0x7aa9d6
      const dot = new THREE.Mesh(new THREE.SphereGeometry((sel ? 0.26 : 0.18) * k, 12, 8),
        new THREE.MeshBasicMaterial({ color, transparent: !!ed?.remove, opacity: ed?.remove ? 0.45 : 1 }))
      dot.userData.actor = n.actor
      dot.position.y = 0.9 * k
      g.add(dot)
      const name = ed?.name ?? n.name
      const l = name ? label(ed?.remove ? `${name}（删掉）` : name, sel ? "#ffe2a8" : n.player ? "#ffd2a0" : "#c7d9ec") : null
      if (l) {
        l.position.y = 1.35 * k
        l.scale.x *= -1 // 抵消 root 的镜像, 字不反
        g.add(l)
      }
      // 原版模型 (act_<ACT>_g0.glb, 已是米制): 放当时的动作 pose_<动作号>, 大小乘这个动作的 ACT 缩放
      if (n.glb && !ed?.remove && !ed?.model) {
        loadGLB(`/gamedata/${n.glb}`).then((gl) => {
          if (stale) return
          const inst = cloneSkinned(gl.scene)
          inst.traverse((o) => {
            const m = o as THREE.Mesh
            if (!m.isMesh) return
            const conv = (src: THREE.Material) => {
              const s2 = src as THREE.MeshStandardMaterial
              return new THREE.MeshBasicMaterial({ map: s2.map ?? null, color: s2.color ?? 0xffffff, transparent: s2.transparent,
                alphaTest: s2.alphaTest, side: s2.side, opacity: s2.opacity })
            }
            m.material = Array.isArray(m.material) ? m.material.map(conv) : conv(m.material)
          })
          inst.traverse((o) => { o.userData.actor = n.actor })
          const holder = new THREE.Group()
          holder.rotation.y = Math.PI - ((ed?.facing ?? n.facing) * Math.PI) / 180 + ORIG_YAW
          const sc = n.scale ?? 1
          inst.scale.set(-sc, sc, sc)
          holder.add(inst)
          g.remove(dot)
          g.add(holder)
          const clip = gl.animations.find((a) => a.name === `pose_${n.pose ?? 0}`) ?? gl.animations.find((a) => a.name === "pose_0")
          if (clip) {
            const mx = new THREE.AnimationMixer(inst)
            mx.clipAction(clip).play()
            t.castMixers.push(mx)
          }
          inst.updateMatrixWorld(true)
          if (l) l.position.y = Math.max(0.6, new THREE.Box3().setFromObject(inst, true).max.y - g.getWorldPosition(new THREE.Vector3()).y + 0.35)
          if (sel) {
            const ring = new THREE.Mesh(new THREE.RingGeometry(0.45, 0.6, 32), new THREE.MeshBasicMaterial({ color: 0xffd27a, side: THREE.DoubleSide, transparent: true, opacity: 0.8 }))
            ring.rotation.x = -Math.PI / 2
            ring.position.y = 0.03
            g.add(ring)
          }
        }).catch(() => {})
      }
    }
    // 有剧情快照: 镜头摆成游戏当时的样子 (同 orig_camera.eye_and_focus: 注视主角 +100, 眼睛 = 注视点 + Rz·Ry·Rx·(0,0,−d);
    // 视口地图坐标和游戏世界坐标一样是 (游戏坐标 + 偏移) × 0.01, 公式直接套; 视野角 = 2·atan(300 / (100·k)))。旧快照没有镜头就斜上方 12 米
    const me = cast?.find((c) => c.player)
    if (me) {
      const focus = toLocal(me.pos).add(new THREE.Vector3(0, 100 * S, 0))
      let eye = focus.clone().add(new THREE.Vector3(0, 7, 10))
      if (snapCam) {
        const [a, b, c] = snapCam.ang.map((x) => (x * Math.PI) / 180)
        let v = new THREE.Vector3(0, 0, -snapCam.d)
        v = new THREE.Vector3(v.x, Math.cos(a) * v.y - Math.sin(a) * v.z, Math.sin(a) * v.y + Math.cos(a) * v.z)   // Rx (列向量 (1,0,0) (0,cos,sin) (0,−sin,cos))
        v = new THREE.Vector3(Math.cos(b) * v.x - Math.sin(b) * v.z, v.y, Math.sin(b) * v.x + Math.cos(b) * v.z)   // Ry
        v = new THREE.Vector3(Math.cos(c) * v.x - Math.sin(c) * v.y, Math.sin(c) * v.x + Math.cos(c) * v.y, v.z)   // Rz
        eye = focus.clone().add(v.multiplyScalar(S))
        t.camera.fov = (2 * Math.atan(300 / (100 * snapCam.k)) * 180) / Math.PI
      }
      t.controls.target.copy(t.root.localToWorld(focus.clone()))
      t.camera.position.copy(t.root.localToWorld(eye))
      t.camera.updateProjectionMatrix()
    }
    return () => {
      stale = true
    }
  }, [detail, loading, k, edits, selectedOrig, cast, snapCam])

  // 遇敌区域: 半透明橙色盒子 (x / z 范围, 高度取场景范围), 标「区域 N」(同遇敌面板)
  useEffect(() => {
    const t = three.current
    if (!t) return
    t.zones.clear()
    if (!showZones || !detail?.zones?.length || loading) return
    const sb = sceneBox(t.scene)
    if (sb.isEmpty()) return
    const h = sb.max.y - sb.min.y
    detail.zones.forEach((z, i) => {
      const w = (z.max[0] - z.min[0]) * S, d = (z.max[1] - z.min[1]) * S
      const cx = ((z.min[0] + z.max[0]) / 2 + detail.offset[0]) * S, cz = ((z.min[1] + z.max[1]) / 2 + detail.offset[2]) * S
      const geo = new THREE.BoxGeometry(w, h, d)
      const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: 0xf0a050, transparent: true, opacity: 0.12, depthWrite: false }))
      m.position.set(cx, sb.min.y + h / 2, cz)
      const edges = new THREE.LineSegments(new THREE.EdgesGeometry(geo), new THREE.LineBasicMaterial({ color: 0xf0a050 }))
      edges.position.copy(m.position)
      const l = label(`区域 ${i + 1}`, "#ffd2a0")
      l.scale.multiplyScalar(1.3)
      l.scale.x *= -1
      l.position.set(cx, sb.max.y + k, cz)
      t.zones.add(m, edges, l)
    })
  }, [detail, showZones, loading, k])

  // 本 mod 的 NPC 标记 (橙色, 带朝向箭头; 选中的加光圈)
  useEffect(() => {
    const t = three.current
    if (!t || !detail) return
    t.mod.clear()
    t.mixers.length = 0
    let stale = false
    for (const n of npcs) {
      const g = new THREE.Group()
      g.userData.local = n.local
      g.scale.setScalar(k)
      g.position.set((n.pos[0] + detail.offset[0]) * S, (n.pos[1] + detail.offset[1]) * S, (n.pos[2] + detail.offset[2]) * S)
      const sel = n.local === selected
      const body = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.28, 1.5, 16), new THREE.MeshBasicMaterial({ color: sel ? 0xffb066 : 0xf0a050 }))
      body.position.y = 0.75
      g.add(body)
      // 用自定义模型的 NPC: 读到模型后换掉圆柱, 播待机动画 (真实大小, 不跟标记缩放 k)
      const cm = n.model > 0 ? models.find((m) => m.local === n.model) : undefined
      if (cm) {
        loadGLB(`/project/${cm.file}`).then((gl) => {
          if (stale) return
          const inst = cloneSkinned(gl.scene)
          // 场景是不受光的 (同原版), 模型也换成不受光材质, 只保留贴图 / 颜色 / 透明
          inst.traverse((o) => {
            const m = o as THREE.Mesh
            if (!m.isMesh) return
            const conv = (src: THREE.Material) => {
              const s = src as THREE.MeshStandardMaterial
              return new THREE.MeshBasicMaterial({ map: s.map ?? null, color: s.color ?? 0xffffff, transparent: s.transparent,
                alphaTest: s.alphaTest, side: s.side, opacity: s.opacity })
            }
            m.material = Array.isArray(m.material) ? m.material.map(conv) : conv(m.material)
          })
          // 根节点 x 镜像 (原版左手坐标) → 模型自身再镜像一次; 正面 +Z 对准朝向箭头: 绕 Y 转 π − 朝向 (+ 朝向修正)
          const holder = new THREE.Group()
          holder.scale.setScalar(1 / k)
          holder.rotation.y = Math.PI - (n.facing * Math.PI) / 180 + (cm.yaw * Math.PI) / 180
          inst.scale.set(-cm.scale, cm.scale, cm.scale)
          inst.position.y = -(cm.ground ?? 0) * cm.scale // 脚底贴地 (同游戏)
          holder.add(inst)
          g.remove(body)
          g.add(holder)
          const clip = gl.animations.find((a) => a.name === cm.idle)
          if (clip) {
            const mx = new THREE.AnimationMixer(inst)
            mx.clipAction(clip).play()
            t.mixers.push(mx)
          }
          inst.updateMatrixWorld(true)
          const h = (new THREE.Box3().setFromObject(inst, true).max.y - g.getWorldPosition(new THREE.Vector3()).y) / k
          l.position.y = Math.max(2, h + 0.4)
        }).catch(() => {})
      }
      // 朝向: 游戏 dir_of(deg) = (sin, 0, −cos)
      const r = (n.facing * Math.PI) / 180
      const arrow = new THREE.ArrowHelper(new THREE.Vector3(Math.sin(r), 0, -Math.cos(r)), new THREE.Vector3(0, 0.1, 0), 0.9, 0xfff3dc, 0.3, 0.2)
      g.add(arrow)
      if (sel) {
        const ring = new THREE.Mesh(new THREE.RingGeometry(0.45, 0.6, 32), new THREE.MeshBasicMaterial({ color: 0xffd9a6, side: THREE.DoubleSide, transparent: true, opacity: 0.8 }))
        ring.rotation.x = -Math.PI / 2
        ring.position.y = 0.03
        g.add(ring)
      }
      const l = label(n.name || `NPC ${n.local}`, "#ffd9a6")
      l.position.y = 2
      l.scale.multiplyScalar(1 / k)   // 标记组整体放大了 k 倍, 名字保持固定屏幕大小
      l.scale.x *= -1
      g.add(l)
      t.mod.add(g)
    }
    return () => {
      stale = true
    }
  }, [npcs, models, selected, detail, k])

  return (
    <div className="relative h-full w-full overflow-hidden">
      <div ref={host} className={`absolute inset-0 ${placing ? "cursor-crosshair" : "cursor-default"}`} />
      {loading && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 bg-background/60 text-sm text-muted-foreground">
          <Spinner className="size-6" />
          正在读取场景…
        </div>
      )}
      {error && (
        <div className="absolute inset-x-4 top-4">
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>场景读取失败</AlertTitle>
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        </div>
      )}
    </div>
  )
}
