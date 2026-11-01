// Go 后端接口 (wailsjs 生成的绑定) 的类型化封装: 参数 / 返回值用 types.ts 的普通对象
import * as Go from "../../wailsjs/go/main/App"
import type { GameMember, GameNewGame, GameSkill, Snapshot, Chapter, EventInfo, Names, Opcode, CustomModel, GameBattlefield, GameItem, GameMonster, Issue, MapDetail, MapInfo, Manifest, Model, Project, Status } from "./types"

/* eslint-disable @typescript-eslint/no-explicit-any */
const P = (p: Project) => p as any

export const api = {
  status: () => Go.GetStatus() as Promise<Status>,
  chooseGameRoot: () => Go.ChooseGameRoot(),
  listMaps: () => Go.ListMaps() as Promise<MapInfo[]>,
  getMap: (id: number) => Go.GetMap(id) as unknown as Promise<MapDetail>,
  listModels: () => Go.ListModels() as Promise<Model[]>,
  floorAt: (map: number, x: number, z: number, y: number) => Go.FloorAt(map, x, z, y) as Promise<{ y: number; ok: boolean }>,
  itemName: (id: number) => Go.ItemName(id),
  chooseDirectory: (title: string) => Go.ChooseDirectory(title),
  newProject: (dir: string, m: Manifest) => Go.NewProject(dir, m as any) as unknown as Promise<Project>,
  openProject: (dir: string) => Go.OpenProject(dir) as unknown as Promise<Project>,
  saveProject: (p: Project) => Go.SaveProject(P(p)),
  validate: (p: Project) => Go.Validate(P(p)) as Promise<Issue[]>,
  playTest: (p: Project, map: number, pos: [number, number, number]) => Go.PlayTest(P(p), map, pos),
  createAuthorKey: () => Go.CreateAuthorKey(),
  packPod: (p: Project) => Go.PackPod(P(p)) as Promise<{ path: string; size: number; files: number; fingerprint: string }>,
  reveal: (path: string) => Go.RevealInFinder(path),
  chooseGLB: () => Go.ChooseGLB(),
  listItems: () => Go.ListItems() as unknown as Promise<GameItem[]>,
  listChapters: () => Go.ListChapters() as unknown as Promise<Chapter[]>,
  getSnapshot: (id: number) => Go.GetSnapshot(id) as unknown as Promise<Snapshot | null>,
  playEvent: (id: number, p: Project | null) => Go.PlayEvent(id, p as any),
  getEvent: (id: number) => Go.GetEvent(id) as unknown as Promise<EventInfo>,
  listOpcodes: () => Go.ListOpcodes() as unknown as Promise<Record<string, Opcode>>,
  getNames: () => Go.GetNames() as unknown as Promise<Names>,
  getMembers: () => Go.GetMembers() as unknown as Promise<{ members: GameMember[]; newGame: GameNewGame }>,
  listSkills: () => Go.ListSkills() as unknown as Promise<GameSkill[]>,
  listMonsters: () => Go.ListMonsters() as unknown as Promise<GameMonster[]>,
  listBattlefields: () => Go.ListBattlefields() as unknown as Promise<GameBattlefield[]>,
  importModel: (p: Project, src: string) =>
    Go.ImportModel(P(p), src) as unknown as Promise<ImportResult>,
  replaceModel: (p: Project, local: number, src: string) =>
    Go.ReplaceModel(P(p), local, src) as unknown as Promise<ImportResult>,
}

export interface ImportResult {
  model: CustomModel
  info: { size: number; triangles: number; textures: number; warnings: string[] }
}

/** Go 返回的 error 在 JS 里是字符串或 Error */
export function errText(e: unknown): string {
  if (typeof e === "string") return e
  if (e instanceof Error) return e.message
  return String(e)
}
