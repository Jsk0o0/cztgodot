package gamedata

import (
	"os"
	"testing"
)

// 原版熊 (1017): 普攻 ATK 17 = 跑 28 + 攻击 17; 技能「熊的煎饺」ATK 323 = 20 / 21; 固定动作 14 / 25 / 26
func TestMonsterPoses(t *testing.T) {
	dir := "../../../extracted"
	if _, err := os.Stat(dir + "/game/battle.json"); err != nil {
		t.Skip("没有游戏数据")
	}
	s := &Store{Extracted: dir}
	ms, err := s.Monsters()
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range ms {
		if m.ID != 1017 {
			continue
		}
		got := map[int]MonsterPose{}
		for _, p := range m.Poses {
			got[p.Q] = p
		}
		for _, q := range []int{14, 25, 26, 28, 17, 20, 21} {
			if _, ok := got[q]; !ok {
				t.Errorf("熊缺动作 %d: %+v", q, m.Poses)
			}
		}
		if got[17].Hits == 0 || got[14].Loop == false {
			t.Errorf("攻击动作应有命中记号、待机应循环: %+v %+v", got[17], got[14])
		}
		return
	}
	t.Fatal("没有熊")
}
