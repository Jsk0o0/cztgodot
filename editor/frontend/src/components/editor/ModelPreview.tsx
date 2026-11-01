import { useEffect, useRef, useState } from "react"
import * as THREE from "three"
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js"
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js"
import { Spinner } from "@/components/ui/spinner"

// 模型预览: 1 单位 = 1 米 (游戏里同样); 旁边放一个 1.6 米高的半透明参考人; 白色箭头 = 模型正面 (glTF +Z, 再转 yaw)
type Props = { url: string; scale: number; yaw: number; anim: string; ground?: number; onHeight?: (h: number) => void }

export function ModelPreview({ url, scale, yaw, anim, ground = 0, onHeight }: Props) {
  const host = useRef<HTMLDivElement>(null)
  const st = useRef<{ holder: THREE.Group; mixer?: THREE.AnimationMixer; clips: THREE.AnimationClip[]; model?: THREE.Object3D } | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const heightCb = useRef(onHeight)
  heightCb.current = onHeight

  useEffect(() => {
    const el = host.current!
    const renderer = new THREE.WebGLRenderer({ antialias: true })
    renderer.setPixelRatio(window.devicePixelRatio)
    renderer.outputColorSpace = THREE.SRGBColorSpace
    el.appendChild(renderer.domElement)
    const scene = new THREE.Scene()
    scene.background = new THREE.Color(0x24201c)
    scene.add(new THREE.HemisphereLight(0xffffff, 0x554433, 2.2))
    const dl = new THREE.DirectionalLight(0xffffff, 1.5)
    dl.position.set(2, 4, 3)
    scene.add(dl)
    scene.add(new THREE.GridHelper(4, 8, 0x6a5a48, 0x3a322b))
    const ref = new THREE.Mesh(new THREE.CapsuleGeometry(0.22, 1.16, 4, 12), new THREE.MeshBasicMaterial({ color: 0x7aa9d6, transparent: true, opacity: 0.25 }))
    ref.position.set(-0.9, 0.8, 0)
    scene.add(ref)
    const holder = new THREE.Group()
    scene.add(holder)
    const camera = new THREE.PerspectiveCamera(35, 1, 0.05, 100)
    camera.position.set(2.2, 1.6, 3.2)
    const controls = new OrbitControls(camera, renderer.domElement)
    controls.target.set(0, 0.85, 0)
    controls.enableDamping = true
    st.current = { holder, clips: [] }
    const fit = () => {
      const r = el.getBoundingClientRect()
      renderer.setSize(r.width, r.height)
      camera.aspect = r.width / Math.max(1, r.height)
      camera.updateProjectionMatrix()
    }
    const ro = new ResizeObserver(fit)
    ro.observe(el)
    fit()
    const clock = new THREE.Clock()
    let raf = 0
    const tick = () => {
      st.current?.mixer?.update(clock.getDelta())
      controls.update()
      renderer.render(scene, camera)
      raf = requestAnimationFrame(tick)
    }
    tick()
    return () => {
      cancelAnimationFrame(raf)
      ro.disconnect()
      controls.dispose()
      renderer.dispose()
      el.removeChild(renderer.domElement)
      st.current = null
    }
  }, [])

  // 读模型
  useEffect(() => {
    const s = st.current
    if (!s) return
    let alive = true
    setLoading(true)
    setError("")
    new GLTFLoader()
      .loadAsync(url)
      .then((g) => {
        if (!alive || !st.current) return
        s.holder.clear()
        s.model = g.scene
        // 原始高度 (模型自己的单位, 还没乘缩放): 挂到缩放节点之前量; precise = 带骨骼的按蒙皮后顶点算 (根节点自带缩放 / 旋转也算上)
        g.scene.updateMatrixWorld(true)
        const box = new THREE.Box3().setFromObject(g.scene, true)
        heightCb.current?.(box.max.y - box.min.y)
        s.holder.add(g.scene)
        const front = new THREE.ArrowHelper(new THREE.Vector3(0, 0, 1), new THREE.Vector3(0, 0.02, 0), 0.7, 0xfff3dc, 0.18, 0.12)
        s.holder.add(front)
        s.clips = g.animations
        s.mixer = new THREE.AnimationMixer(g.scene)
      })
      .catch((e) => alive && setError(String(e?.message ?? e)))
      .finally(() => alive && setLoading(false))
    return () => {
      alive = false
    }
  }, [url])

  // 缩放 / 朝向 / 动画
  useEffect(() => {
    const s = st.current
    if (!s) return
    s.holder.scale.setScalar(scale)
    s.holder.rotation.y = (yaw * Math.PI) / 180
    if (s.model) s.model.position.y = -ground // 脚底贴地 (同游戏)
    if (s.mixer) {
      s.mixer.stopAllAction()
      const c = s.clips.find((x) => x.name === anim)
      if (c) s.mixer.clipAction(c).play()
    }
  }, [scale, yaw, anim, ground, loading])

  return (
    <div className="relative h-56 w-full overflow-hidden rounded-md border">
      <div ref={host} className="absolute inset-0" />
      {loading && <div className="absolute inset-0 flex items-center justify-center gap-2 bg-background/60 text-xs text-muted-foreground"><Spinner />正在读取模型…</div>}
      {error && <div className="absolute inset-x-2 bottom-2 rounded bg-destructive/20 p-2 text-xs text-destructive">{error}</div>}
      <div className="pointer-events-none absolute bottom-1.5 left-2 text-[11px] text-muted-foreground">蓝色参考人 1.6 米 · 白色箭头 = 正面</div>
    </div>
  )
}
