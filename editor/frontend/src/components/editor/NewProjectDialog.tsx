import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Spinner } from "@/components/ui/spinner"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field"
import { FolderOpenIcon } from "lucide-react"
import { api, errText } from "@/lib/api"
import type { Manifest, Project } from "@/lib/types"

const ID_RE = /^[a-z0-9][a-z0-9_-]*\.[a-z0-9][a-z0-9_.-]*$/

export function NewProjectDialog({ open, onOpenChange, onCreated }: { open: boolean; onOpenChange: (v: boolean) => void; onCreated: (p: Project) => void }) {
  const [m, setM] = useState<Manifest>({ id: "", name: "", version: "0.1.0", author: "", game: "0.4", description: "" })
  const [dir, setDir] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState("")
  const idBad = m.id !== "" && !ID_RE.test(m.id)
  const ok = ID_RE.test(m.id) && m.name.trim() !== "" && dir !== "" && !busy

  const pick = async () => {
    const d = await api.chooseDirectory("选择一个空目录存放方案").catch(() => "")
    if (d) setDir(d)
  }
  const create = async () => {
    setBusy(true)
    setError("")
    try {
      onCreated(await api.newProject(dir, m))
      onOpenChange(false)
    } catch (e) {
      setError(errText(e))
    } finally {
      setBusy(false)
    }
  }
  return (
    <Dialog open={open} onOpenChange={(v) => !busy && onOpenChange(v)}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>新建方案</DialogTitle>
          <DialogDescription>方案就是一个文件夹：在原版基础上的修改和新增都存在这里。游戏可以直接用开发模式加载它，打包后得到 .pod 分享。</DialogDescription>
        </DialogHeader>
        <FieldGroup>
          <Field data-invalid={idBad || undefined}>
            <FieldLabel htmlFor="nid">ID</FieldLabel>
            <Input id="nid" placeholder="例如 kp.cheyun-gold" value={m.id} aria-invalid={idBad}
              onChange={(e) => setM({ ...m, id: e.target.value.trim() })} />
            {idBad ? <FieldError>写成「作者.名字」，只用小写字母、数字、- 和 _</FieldError>
              : <FieldDescription>打包分发后不要再改，存档靠它找 mod。</FieldDescription>}
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field>
              <FieldLabel htmlFor="nname">名称</FieldLabel>
              <Input id="nname" placeholder="车芸的盘缠" value={m.name} onChange={(e) => setM({ ...m, name: e.target.value })} />
            </Field>
            <Field>
              <FieldLabel htmlFor="nauthor">作者</FieldLabel>
              <Input id="nauthor" value={m.author} onChange={(e) => setM({ ...m, author: e.target.value })} />
            </Field>
          </div>
          <Field>
            <FieldLabel htmlFor="ndesc">简介</FieldLabel>
            <Textarea id="ndesc" rows={3} value={m.description} onChange={(e) => setM({ ...m, description: e.target.value })} />
          </Field>
          <Field>
            <FieldLabel>方案目录</FieldLabel>
            <div className="flex gap-2">
              <Input readOnly value={dir} placeholder="选择一个空目录" className="flex-1" />
              <Button variant="outline" onClick={pick}><FolderOpenIcon />选择</Button>
            </div>
          </Field>
          {error && <FieldError>{error}</FieldError>}
        </FieldGroup>
        <DialogFooter>
          <Button variant="outline" disabled={busy} onClick={() => onOpenChange(false)}>取消</Button>
          <Button disabled={!ok} onClick={create}>{busy && <Spinner />}创建</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
