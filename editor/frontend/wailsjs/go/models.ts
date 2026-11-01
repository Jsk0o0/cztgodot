export namespace gamedata {
	
	export class BattleSlot {
	    monster: number;
	    name: string;
	    pos: number[];
	    facing: number;
	
	    static createFrom(source: any = {}) {
	        return new BattleSlot(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.monster = source["monster"];
	        this.name = source["name"];
	        this.pos = source["pos"];
	        this.facing = source["facing"];
	    }
	}
	export class Battlefield {
	    id: number;
	    name: string;
	    scene: string;
	    slots: BattleSlot[];
	    initiative: number;
	
	    static createFrom(source: any = {}) {
	        return new Battlefield(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.scene = source["scene"];
	        this.slots = this.convertValues(source["slots"], BattleSlot);
	        this.initiative = source["initiative"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Box {
	    event: number;
	    min: number[];
	    max: number[];
	
	    static createFrom(source: any = {}) {
	        return new Box(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.event = source["event"];
	        this.min = source["min"];
	        this.max = source["max"];
	    }
	}
	export class CastMember {
	    actor: number;
	    name: string;
	    act: number;
	    pose: number;
	    pos: number[];
	    facing: number;
	    event: number;
	    player: boolean;
	    glb: string;
	    scale: number;
	
	    static createFrom(source: any = {}) {
	        return new CastMember(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.actor = source["actor"];
	        this.name = source["name"];
	        this.act = source["act"];
	        this.pose = source["pose"];
	        this.pos = source["pos"];
	        this.facing = source["facing"];
	        this.event = source["event"];
	        this.player = source["player"];
	        this.glb = source["glb"];
	        this.scale = source["scale"];
	    }
	}
	export class Task {
	    title: string;
	    main: boolean;
	    done: boolean;
	    events: StoryEvent[];
	
	    static createFrom(source: any = {}) {
	        return new Task(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.title = source["title"];
	        this.main = source["main"];
	        this.done = source["done"];
	        this.events = this.convertValues(source["events"], StoryEvent);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class StoryEvent {
	    id: number;
	    map: string;
	    mid: number;
	    trig: string;
	    talk: number;
	    acc: string[];
	    comp: string[];
	    name: string;
	    first: string;
	    reached: boolean;
	    kind: string;
	    time: number;
	
	    static createFrom(source: any = {}) {
	        return new StoryEvent(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.map = source["map"];
	        this.mid = source["mid"];
	        this.trig = source["trig"];
	        this.talk = source["talk"];
	        this.acc = source["acc"];
	        this.comp = source["comp"];
	        this.name = source["name"];
	        this.first = source["first"];
	        this.reached = source["reached"];
	        this.kind = source["kind"];
	        this.time = source["time"];
	    }
	}
	export class Chapter {
	    key: string;
	    group: string;
	    title: string;
	    sub: string;
	    events: StoryEvent[];
	    tasks: Task[];
	    side: Task[];
	
	    static createFrom(source: any = {}) {
	        return new Chapter(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.key = source["key"];
	        this.group = source["group"];
	        this.title = source["title"];
	        this.sub = source["sub"];
	        this.events = this.convertValues(source["events"], StoryEvent);
	        this.tasks = this.convertValues(source["tasks"], Task);
	        this.side = this.convertValues(source["side"], Task);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class EventInfo {
	    id: number;
	    file: string;
	    code: any[][];
	    shared: number[];
	    triggers: string[];
	    lines: string[];
	    battles: string[];
	    maps: number[];
	
	    static createFrom(source: any = {}) {
	        return new EventInfo(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.file = source["file"];
	        this.code = source["code"];
	        this.shared = source["shared"];
	        this.triggers = source["triggers"];
	        this.lines = source["lines"];
	        this.battles = source["battles"];
	        this.maps = source["maps"];
	    }
	}
	export class Item {
	    id: number;
	    name: string;
	    sub: number;
	    cat: string;
	    price: number;
	    desc: string;
	    icon: string;
	    fx1: number[];
	    fx2: number[];
	
	    static createFrom(source: any = {}) {
	        return new Item(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.sub = source["sub"];
	        this.cat = source["cat"];
	        this.price = source["price"];
	        this.desc = source["desc"];
	        this.icon = source["icon"];
	        this.fx1 = source["fx1"];
	        this.fx2 = source["fx2"];
	    }
	}
	export class Zone {
	    min: number[];
	    max: number[];
	    battles: number[];
	    names: string[];
	
	    static createFrom(source: any = {}) {
	        return new Zone(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.min = source["min"];
	        this.max = source["max"];
	        this.battles = source["battles"];
	        this.names = source["names"];
	    }
	}
	export class Npc {
	    actor: number;
	    name: string;
	    act: number;
	    pos: number[];
	    facing: number;
	    event: number;
	
	    static createFrom(source: any = {}) {
	        return new Npc(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.actor = source["actor"];
	        this.name = source["name"];
	        this.act = source["act"];
	        this.pos = source["pos"];
	        this.facing = source["facing"];
	        this.event = source["event"];
	    }
	}
	export class MapDetail {
	    id: number;
	    name: string;
	    title: string;
	    kind: string;
	    scene: string;
	    offset: number[];
	    npcs: Npc[];
	    boxes: Box[];
	    zones: Zone[];
	
	    static createFrom(source: any = {}) {
	        return new MapDetail(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.title = source["title"];
	        this.kind = source["kind"];
	        this.scene = source["scene"];
	        this.offset = source["offset"];
	        this.npcs = this.convertValues(source["npcs"], Npc);
	        this.boxes = this.convertValues(source["boxes"], Box);
	        this.zones = this.convertValues(source["zones"], Zone);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class MapInfo {
	    id: number;
	    name: string;
	    title: string;
	    kind: string;
	
	    static createFrom(source: any = {}) {
	        return new MapInfo(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.title = source["title"];
	        this.kind = source["kind"];
	    }
	}
	export class Model {
	    act: number;
	    label: string;
	    glb: string;
	
	    static createFrom(source: any = {}) {
	        return new Model(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.act = source["act"];
	        this.label = source["label"];
	        this.glb = source["glb"];
	    }
	}
	export class MonsterPose {
	    q: number;
	    ticks: number;
	    loop: boolean;
	    hits: number;
	    uses: string[];
	
	    static createFrom(source: any = {}) {
	        return new MonsterPose(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.q = source["q"];
	        this.ticks = source["ticks"];
	        this.loop = source["loop"];
	        this.hits = source["hits"];
	        this.uses = source["uses"];
	    }
	}
	export class Monster {
	    id: number;
	    name: string;
	    race: string;
	    desc: string;
	    level: number;
	    hp: number;
	    mp: number;
	    sp: number;
	    atk: number;
	    def: number;
	    spd: number;
	    matk: number;
	    mdef: number;
	    hit: number;
	    eva: number;
	    mhit: number;
	    meva: number;
	    exp: number;
	    money: number;
	    drop: number[];
	    boss: boolean;
	    glb: string;
	    poses: MonsterPose[];
	    scale: number;
	
	    static createFrom(source: any = {}) {
	        return new Monster(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.race = source["race"];
	        this.desc = source["desc"];
	        this.level = source["level"];
	        this.hp = source["hp"];
	        this.mp = source["mp"];
	        this.sp = source["sp"];
	        this.atk = source["atk"];
	        this.def = source["def"];
	        this.spd = source["spd"];
	        this.matk = source["matk"];
	        this.mdef = source["mdef"];
	        this.hit = source["hit"];
	        this.eva = source["eva"];
	        this.mhit = source["mhit"];
	        this.meva = source["meva"];
	        this.exp = source["exp"];
	        this.money = source["money"];
	        this.drop = source["drop"];
	        this.boss = source["boss"];
	        this.glb = source["glb"];
	        this.poses = this.convertValues(source["poses"], MonsterPose);
	        this.scale = source["scale"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	
	export class Names {
	    people: Record<string, string>;
	    items: Record<string, string>;
	    battles: Record<string, string>;
	
	    static createFrom(source: any = {}) {
	        return new Names(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.people = source["people"];
	        this.items = source["items"];
	        this.battles = source["battles"];
	    }
	}
	
	export class Skill {
	    id: number;
	    name: string;
	    desc: string;
	    sub: number;
	    cat: string;
	    note: string;
	    power: number;
	    cost: Record<string, number>;
	    fx1: number[];
	    fx2: number[];
	    owner: number;
	    copy: boolean;
	
	    static createFrom(source: any = {}) {
	        return new Skill(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.desc = source["desc"];
	        this.sub = source["sub"];
	        this.cat = source["cat"];
	        this.note = source["note"];
	        this.power = source["power"];
	        this.cost = source["cost"];
	        this.fx1 = source["fx1"];
	        this.fx2 = source["fx2"];
	        this.owner = source["owner"];
	        this.copy = source["copy"];
	    }
	}
	export class SnapCam {
	    ang: number[];
	    d: number;
	    k: number;
	
	    static createFrom(source: any = {}) {
	        return new SnapCam(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.ang = source["ang"];
	        this.d = source["d"];
	        this.k = source["k"];
	    }
	}
	export class Snapshot {
	    event: number;
	    borrowed: number;
	    map: number;
	    playSeconds: number;
	    cast: CastMember[];
	    cam?: SnapCam;
	
	    static createFrom(source: any = {}) {
	        return new Snapshot(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.event = source["event"];
	        this.borrowed = source["borrowed"];
	        this.map = source["map"];
	        this.playSeconds = source["playSeconds"];
	        this.cast = this.convertValues(source["cast"], CastMember);
	        this.cam = this.convertValues(source["cam"], SnapCam);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	
	

}

export namespace main {
	
	export class Floor {
	    y: number;
	    ok: boolean;
	
	    static createFrom(source: any = {}) {
	        return new Floor(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.y = source["y"];
	        this.ok = source["ok"];
	    }
	}
	export class ImportResult {
	    model: project.Model;
	    info: project.GLBInfo;
	
	    static createFrom(source: any = {}) {
	        return new ImportResult(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.model = this.convertValues(source["model"], project.Model);
	        this.info = this.convertValues(source["info"], project.GLBInfo);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class PackResult {
	    path: string;
	    size: number;
	    files: number;
	    fingerprint: string;
	
	    static createFrom(source: any = {}) {
	        return new PackResult(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.path = source["path"];
	        this.size = source["size"];
	        this.files = source["files"];
	        this.fingerprint = source["fingerprint"];
	    }
	}
	export class Status {
	    gameRoot: string;
	    dataOk: boolean;
	    error: string;
	    godot: string;
	    godotOk: boolean;
	    authorKey: boolean;
	
	    static createFrom(source: any = {}) {
	        return new Status(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.gameRoot = source["gameRoot"];
	        this.dataOk = source["dataOk"];
	        this.error = source["error"];
	        this.godot = source["godot"];
	        this.godotOk = source["godotOk"];
	        this.authorKey = source["authorKey"];
	    }
	}

}

export namespace project {
	
	export class Anim {
	    name: string;
	    seconds: number;
	
	    static createFrom(source: any = {}) {
	        return new Anim(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.name = source["name"];
	        this.seconds = source["seconds"];
	    }
	}
	export class Enemy {
	    at: number;
	    monster?: number;
	    modMonster?: number;
	
	    static createFrom(source: any = {}) {
	        return new Enemy(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.at = source["at"];
	        this.monster = source["monster"];
	        this.modMonster = source["modMonster"];
	    }
	}
	export class Battle {
	    local: number;
	    name: string;
	    base: number;
	    enemies: Enemy[];
	
	    static createFrom(source: any = {}) {
	        return new Battle(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.local = source["local"];
	        this.name = source["name"];
	        this.base = source["base"];
	        this.enemies = this.convertValues(source["enemies"], Enemy);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Goods {
	    item?: number;
	    modItem?: number;
	
	    static createFrom(source: any = {}) {
	        return new Goods(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.item = source["item"];
	        this.modItem = source["modItem"];
	    }
	}
	export class Block {
	    type: string;
	    speaker?: string;
	    text?: string;
	    amount?: number;
	    item?: number;
	    modItem?: number;
	    itemName?: string;
	    goods?: Goods[];
	    count?: number;
	    quiet?: boolean;
	    flag?: number;
	    on?: boolean;
	    quest?: number;
	    step?: string;
	    state?: string;
	    battle?: number;
	    member?: number;
	    var?: number;
	    op?: string;
	    cmp?: string;
	    value?: number;
	    then?: Block[];
	    else?: Block[];
	
	    static createFrom(source: any = {}) {
	        return new Block(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.type = source["type"];
	        this.speaker = source["speaker"];
	        this.text = source["text"];
	        this.amount = source["amount"];
	        this.item = source["item"];
	        this.modItem = source["modItem"];
	        this.itemName = source["itemName"];
	        this.goods = this.convertValues(source["goods"], Goods);
	        this.count = source["count"];
	        this.quiet = source["quiet"];
	        this.flag = source["flag"];
	        this.on = source["on"];
	        this.quest = source["quest"];
	        this.step = source["step"];
	        this.state = source["state"];
	        this.battle = source["battle"];
	        this.member = source["member"];
	        this.var = source["var"];
	        this.op = source["op"];
	        this.cmp = source["cmp"];
	        this.value = source["value"];
	        this.then = this.convertValues(source["then"], Block);
	        this.else = this.convertValues(source["else"], Block);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class SkillRef {
	    skill?: number;
	    modSkill?: number;
	
	    static createFrom(source: any = {}) {
	        return new SkillRef(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.skill = source["skill"];
	        this.modSkill = source["modSkill"];
	    }
	}
	export class GrowthRow {
	    lv: number;
	    inc: number[];
	    learn: SkillRef;
	
	    static createFrom(source: any = {}) {
	        return new GrowthRow(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.lv = source["lv"];
	        this.inc = source["inc"];
	        this.learn = this.convertValues(source["learn"], SkillRef);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class CharEdit {
	    id: number;
	    name?: string;
	    desc?: string;
	    stats?: Record<string, number>;
	    growth?: GrowthRow[];
	    mapAct?: number;
	    mapModel?: number;
	
	    static createFrom(source: any = {}) {
	        return new CharEdit(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.desc = source["desc"];
	        this.stats = source["stats"];
	        this.growth = this.convertValues(source["growth"], GrowthRow);
	        this.mapAct = source["mapAct"];
	        this.mapModel = source["mapModel"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Encounter {
	    map: number;
	    battle: number;
	    weight: number;
	    zones: number[];
	
	    static createFrom(source: any = {}) {
	        return new Encounter(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.map = source["map"];
	        this.battle = source["battle"];
	        this.weight = source["weight"];
	        this.zones = source["zones"];
	    }
	}
	
	export class Event {
	    local: number;
	    name: string;
	    blocks: Block[];
	
	    static createFrom(source: any = {}) {
	        return new Event(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.local = source["local"];
	        this.name = source["name"];
	        this.blocks = this.convertValues(source["blocks"], Block);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Flag {
	    local: number;
	    name: string;
	
	    static createFrom(source: any = {}) {
	        return new Flag(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.local = source["local"];
	        this.name = source["name"];
	    }
	}
	export class GLBInfo {
	    size: number;
	    triangles: number;
	    anims: Anim[];
	    textures: number;
	    warnings: string[];
	
	    static createFrom(source: any = {}) {
	        return new GLBInfo(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.size = source["size"];
	        this.triangles = source["triangles"];
	        this.anims = this.convertValues(source["anims"], Anim);
	        this.textures = source["textures"];
	        this.warnings = source["warnings"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	
	
	export class Issue {
	    level: string;
	    where: string;
	    message: string;
	
	    static createFrom(source: any = {}) {
	        return new Issue(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.level = source["level"];
	        this.where = source["where"];
	        this.message = source["message"];
	    }
	}
	export class Item {
	    local: number;
	    base: number;
	    name: string;
	    desc: string;
	    price: number;
	    fx1?: number[];
	    fx2?: number[];
	
	    static createFrom(source: any = {}) {
	        return new Item(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.local = source["local"];
	        this.base = source["base"];
	        this.name = source["name"];
	        this.desc = source["desc"];
	        this.price = source["price"];
	        this.fx1 = source["fx1"];
	        this.fx2 = source["fx2"];
	    }
	}
	export class ItemRefP {
	    item?: number;
	    modItem?: number;
	
	    static createFrom(source: any = {}) {
	        return new ItemRefP(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.item = source["item"];
	        this.modItem = source["modItem"];
	    }
	}
	export class Manifest {
	    id: string;
	    name: string;
	    version: string;
	    author: string;
	    game: string;
	    description: string;
	
	    static createFrom(source: any = {}) {
	        return new Manifest(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.version = source["version"];
	        this.author = source["author"];
	        this.game = source["game"];
	        this.description = source["description"];
	    }
	}
	export class ModSkill {
	    local: number;
	    base: number;
	    name: string;
	    desc: string;
	    power: number;
	    cost: Record<string, number>;
	    fx1?: number[];
	    fx2?: number[];
	
	    static createFrom(source: any = {}) {
	        return new ModSkill(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.local = source["local"];
	        this.base = source["base"];
	        this.name = source["name"];
	        this.desc = source["desc"];
	        this.power = source["power"];
	        this.cost = source["cost"];
	        this.fx1 = source["fx1"];
	        this.fx2 = source["fx2"];
	    }
	}
	export class Model {
	    local: number;
	    name: string;
	    file: string;
	    scale: number;
	    yaw: number;
	    idle: string;
	    walk: string;
	    ground: number;
	    anims: Anim[];
	    triangles: number;
	    size: number;
	
	    static createFrom(source: any = {}) {
	        return new Model(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.local = source["local"];
	        this.name = source["name"];
	        this.file = source["file"];
	        this.scale = source["scale"];
	        this.yaw = source["yaw"];
	        this.idle = source["idle"];
	        this.walk = source["walk"];
	        this.ground = source["ground"];
	        this.anims = this.convertValues(source["anims"], Anim);
	        this.triangles = source["triangles"];
	        this.size = source["size"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class Monster {
	    local: number;
	    base: number;
	    name: string;
	    desc: string;
	    level: number;
	    hp: number;
	    mp: number;
	    sp: number;
	    atk: number;
	    def: number;
	    spd: number;
	    matk: number;
	    mdef: number;
	    hit: number;
	    eva: number;
	    mhit: number;
	    meva: number;
	    exp: number;
	    money: number;
	    dropRate: number;
	    dropItem?: number;
	    dropModItem?: number;
	    counter?: number;
	    model?: number;
	    poses?: Record<string, string>;
	
	    static createFrom(source: any = {}) {
	        return new Monster(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.local = source["local"];
	        this.base = source["base"];
	        this.name = source["name"];
	        this.desc = source["desc"];
	        this.level = source["level"];
	        this.hp = source["hp"];
	        this.mp = source["mp"];
	        this.sp = source["sp"];
	        this.atk = source["atk"];
	        this.def = source["def"];
	        this.spd = source["spd"];
	        this.matk = source["matk"];
	        this.mdef = source["mdef"];
	        this.hit = source["hit"];
	        this.eva = source["eva"];
	        this.mhit = source["mhit"];
	        this.meva = source["meva"];
	        this.exp = source["exp"];
	        this.money = source["money"];
	        this.dropRate = source["dropRate"];
	        this.dropItem = source["dropItem"];
	        this.dropModItem = source["dropModItem"];
	        this.counter = source["counter"];
	        this.model = source["model"];
	        this.poses = source["poses"];
	    }
	}
	export class NPC {
	    local: number;
	    map: number;
	    name: string;
	    act: number;
	    model: number;
	    pose: number;
	    pos: number[];
	    facing: number;
	    talk: boolean;
	    event: number;
	
	    static createFrom(source: any = {}) {
	        return new NPC(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.local = source["local"];
	        this.map = source["map"];
	        this.name = source["name"];
	        this.act = source["act"];
	        this.model = source["model"];
	        this.pose = source["pose"];
	        this.pos = source["pos"];
	        this.facing = source["facing"];
	        this.talk = source["talk"];
	        this.event = source["event"];
	    }
	}
	export class NewGameEdit {
	    money?: number;
	    items?: ItemRefP[];
	    party?: number[];
	    skills?: Record<string, Array<SkillRef>>;
	    equip?: Record<string, Array<number>>;
	
	    static createFrom(source: any = {}) {
	        return new NewGameEdit(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.money = source["money"];
	        this.items = this.convertValues(source["items"], ItemRefP);
	        this.party = source["party"];
	        this.skills = this.convertValues(source["skills"], Array<SkillRef>, true);
	        this.equip = source["equip"];
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	export class NpcEdit {
	    map: number;
	    actor: number;
	    remove?: boolean;
	    pos?: number[];
	    act?: number;
	    model?: number;
	    facing?: number;
	    event?: number;
	    modEvent?: number;
	    name?: string;
	
	    static createFrom(source: any = {}) {
	        return new NpcEdit(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.map = source["map"];
	        this.actor = source["actor"];
	        this.remove = source["remove"];
	        this.pos = source["pos"];
	        this.act = source["act"];
	        this.model = source["model"];
	        this.facing = source["facing"];
	        this.event = source["event"];
	        this.modEvent = source["modEvent"];
	        this.name = source["name"];
	    }
	}
	export class Override {
	    id: number;
	    name: string;
	    code: any[][];
	
	    static createFrom(source: any = {}) {
	        return new Override(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.code = source["code"];
	    }
	}
	export class SkillEdit {
	    id: number;
	    name?: string;
	    desc?: string;
	    power?: number;
	    cost?: Record<string, number>;
	
	    static createFrom(source: any = {}) {
	        return new SkillEdit(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.id = source["id"];
	        this.name = source["name"];
	        this.desc = source["desc"];
	        this.power = source["power"];
	        this.cost = source["cost"];
	    }
	}
	export class Var {
	    local: number;
	    name: string;
	
	    static createFrom(source: any = {}) {
	        return new Var(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.local = source["local"];
	        this.name = source["name"];
	    }
	}
	export class Quest {
	    local: number;
	    title: string;
	    main: boolean;
	
	    static createFrom(source: any = {}) {
	        return new Quest(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.local = source["local"];
	        this.title = source["title"];
	        this.main = source["main"];
	    }
	}
	export class Project {
	    dir: string;
	    manifest: Manifest;
	    npcs: NPC[];
	    events: Event[];
	    flags: Flag[];
	    models: Model[];
	    items: Item[];
	    quests: Quest[];
	    monsters: Monster[];
	    battles: Battle[];
	    vars: Var[];
	    encounters: Encounter[];
	    overrides: Override[];
	    npcEdits: NpcEdit[];
	    characters: CharEdit[];
	    newGame?: NewGameEdit;
	    skills: ModSkill[];
	    skillEdits: SkillEdit[];
	
	    static createFrom(source: any = {}) {
	        return new Project(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.dir = source["dir"];
	        this.manifest = this.convertValues(source["manifest"], Manifest);
	        this.npcs = this.convertValues(source["npcs"], NPC);
	        this.events = this.convertValues(source["events"], Event);
	        this.flags = this.convertValues(source["flags"], Flag);
	        this.models = this.convertValues(source["models"], Model);
	        this.items = this.convertValues(source["items"], Item);
	        this.quests = this.convertValues(source["quests"], Quest);
	        this.monsters = this.convertValues(source["monsters"], Monster);
	        this.battles = this.convertValues(source["battles"], Battle);
	        this.vars = this.convertValues(source["vars"], Var);
	        this.encounters = this.convertValues(source["encounters"], Encounter);
	        this.overrides = this.convertValues(source["overrides"], Override);
	        this.npcEdits = this.convertValues(source["npcEdits"], NpcEdit);
	        this.characters = this.convertValues(source["characters"], CharEdit);
	        this.newGame = this.convertValues(source["newGame"], NewGameEdit);
	        this.skills = this.convertValues(source["skills"], ModSkill);
	        this.skillEdits = this.convertValues(source["skillEdits"], SkillEdit);
	    }
	
		convertValues(a: any, classs: any, asMap: boolean = false): any {
		    if (!a) {
		        return a;
		    }
		    if (a.slice && a.map) {
		        return (a as any[]).map(elem => this.convertValues(elem, classs));
		    } else if ("object" === typeof a) {
		        if (asMap) {
		            for (const key of Object.keys(a)) {
		                a[key] = new classs(a[key]);
		            }
		            return a;
		        }
		        return new classs(a);
		    }
		    return a;
		}
	}
	
	
	

}

