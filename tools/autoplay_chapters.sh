#!/bin/zsh
# 分段自动通关: 序章 → 第二段 → … → 终章。每段执行到下一段任一剧情事件 (extracted/story/data/chNN.js 的事件号) 即存档 (存档位 90+段号),
# 下一段从该存档继续; 卡住 / 超时存到 80+段号。用法: tools/autoplay_chapters.sh [起始段号 1..10] [起始存档位]   日志: out/ap/stageN.log
GD=/Applications/Godot-stable.app/Contents/MacOS/Godot
cd "$(dirname $0)/../godot"
COMMON=(--sd --autoplay --speed=4 --auto-battle --auto-advance=0.05 --no-encounter --ap-limit=5400)
# SNAP=目录: 顺便录剧情快照 (每个事件第一次执行前的存档状态 + 在场角色, 编辑器按真实剧情顺序浏览 / 播放预览用)。
# 每段先录到 $SNAP/.stageN (快照文件已存在就不写, 所以不能直接录进正式目录: 失败那次留下的会挡住跑通那次的),
# 这段 DONE 了才并入: 先删掉正式目录里 stage = N 的旧快照, 再把这次的覆盖进去。ONLY=1 只跑起始那一段。
snapargs() { [[ -n "$SNAP" ]] && { rm -rf "$SNAP/.stage$1"; echo "--snap-dir=$SNAP/.stage$1 --snap-stage=$1"; } }
promote() {
  [[ -z "$SNAP" ]] && return
  python3 - "$SNAP" "$1" <<'PY'
import glob, json, os, shutil, sys
snap, n = sys.argv[1], int(sys.argv[2])
for f in glob.glob(os.path.join(snap, "*.json")):
    try:
        if json.load(open(f)).get("stage") == n:
            os.remove(f)
    except Exception:
        pass
new = glob.glob(os.path.join(snap, ".stage%d" % n, "*.json"))
for f in new:
    shutil.move(f, os.path.join(snap, os.path.basename(f)))
print("快照: 第 %d 段并入 %d 个" % (n, len(new)))
PY
}
goal() {
  case $1 in
  2) GOAL=201,202,203,204,205,206,207,208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,231,232,233,234,235,236,237,238 ;;
  3) GOAL=251,252,253,254,255,256,257,258,259,260,261,262,263,264,265,266,267,268,269,270,271,272,273,274,275,276,277,278,279,301,302,303,304,305,306,307,308,309,451,452,453,454 ;;
  4) GOAL=501,502,503,504,505,506,507,508,509,510,511,512,513,514,515,516,517,518,519,520,521,522,523,524,525,526,527,528,529,530,531,532,533,534,535,536,538,539,540,541,542,543,545,551,552,553,554,555,556,557,558,559,560,561,601,602,603,604,605,606,607,608,609,610,611,612,613,614,615,620,649 ;;
  5) GOAL=650,651,652,653,654,655,656,657,658,659,660,661,662,663,664,665,666,699,700,701,702,703,704,705,706,707,708,709,710,711,712,713,715,716 ;;
  6) GOAL=751,752,753,754,755,756,757,758,759,760,761,762,763,764,765,766,767,768,769,770,771,772,773,774,775,776,777,778,779,780,781,782,783,784,785,786,791,796,797,798,799 ;;
  7) GOAL=800,801,802,803,804,805,806,807,808,809,810,811,812,813,814,815,816,817,818,851,852,853,854,855,856,857,858,859,900 ;;
  8) GOAL=1001,1002,1003,1004,1005,1006,1007,1008,1009,1010,1011,1012,1013,1014,1040,1041,1042,1043,1044,1045,1046,1047,1048,1049,1050,1051,1052,1053,1054,1055,1056,1057,1058,1059,1060,1061,1062,1063,1064,1065,1066,1067,1068,1071,1072,1073,1081,1082,1083,1084,1085,1086,1087,1088,1089,1090,1091,1092,1093,1094,1095,1096,1097,1098,1099 ;;
  9) GOAL=1501,1502,1503,1504,1505,1506,1507,1508,1509,1510,1511,1512,1513,1514,1515,1516,1517,1518,1519,1520,1531,1532,1533,1534,1535,1536,1537,1538,1539,1540,1541,1542,1543,1544,1545,1546,1547,1551,1552,1553,1554,1555,1556,1557,1558,1559,1560,1562,1563,1564,1565,1566,1567,1568,1569,1570,1571,1572 ;;
  10) GOAL=1564,1612 ;;   # 1564 登上台阶 → call 1612: 结局动画 ending.bik + 名单 TW_list.bik 后 return_to_title
  esac
  echo $GOAL
}
start=${1:-1}
if [[ $start -le 1 ]]; then
  echo "== stage 1 (序章)"
  $GD --headless --path . res://scenes/field.tscn -- $COMMON ${=$(snapargs 1)} --ap-save=91 --ap-save-any=81 > ../out/ap/stage1.log 2>&1
  grep -E "^AP .*(DONE|STUCK|LIMIT)" ../out/ap/stage1.log | tail -1
  grep -qE "^AP .* DONE" ../out/ap/stage1.log || exit 1
  promote 1
  [[ -n "$ONLY" ]] && exit 0
  start=2
fi
slot=${2:-$((89+start))}
for n in {$start..10}; do
  echo "== stage $n (存档 $slot)"
  $GD --headless --path . res://scenes/field.tscn -- $COMMON ${=$(snapargs $n)} --load=$slot --ap-goal=events:$(goal $n) --ap-save=$((90+n)) --ap-save-any=$((80+n)) > ../out/ap/stage$n.log 2>&1
  grep -E "^AP .*(DONE|STUCK|LIMIT)|SCRIPT ERROR" ../out/ap/stage$n.log | tail -3 | cut -c1-200
  grep -qE "^AP .* DONE" ../out/ap/stage$n.log || exit 1
  promote $n
  [[ -n "$ONLY" ]] && exit 0
  slot=$((90+n))
done
echo ALL DONE
