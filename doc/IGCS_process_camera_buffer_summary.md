# IGCS `process_camera_buffer_from_igcs` 处理逻辑分类（gcv_games）

统计：当前 `gcv_games` 里共有 43 个实现，按处理逻辑归为 14 类（11 类 Euler 输入、3 类 Matrix 输入）。

## 逻辑概览表

| ID | 输入 | 旋转/坐标处理（整体变化） | 平移处理 | 输出矩阵变化 |
|---|---|---|---|---|
| E1 | Euler | `R_ue = Rz(-yaw) * Ry(pitch) * Rx(roll)`；UE→CV 轴交换 `(x,y,z)->(y,-z,x)`；`R_cv` 写入时第 2/3 列取负 | `t = (y, -z, x) * scale` | `R` 的第 2/3 列取负 |
| E2 | Euler | `R_ue = Rz(-yaw) * Ry(-pitch) * Rx(roll)`；UE→CV 轴交换 | `t = (x, -y, -z) * 0.2` | `R` 的第 2/3 列取负 |
| E3 | Euler | `R_ue = Rz(yaw) * Ry(-pitch) * Rx(-roll)`；UE→CV 轴交换 | `t = (x, y, z) * 0.5` | 不额外取负 |
| E4 | Euler | 参数顺序交换：`Rx(yaw) * Ry(roll) * Rz(pitch)`；UE→CV 轴交换 | `t = (x, -z, y) * 0.5` | `R` 的第 2/3 列取负 |
| E5 | Euler（列向量法） | 由 `roll/pitch/yaw` 直接生成 `c2w` 三列；UE→CV（`M_UE_to_CV` 与 `M_T`） | 先算 `camera_target_pos=(y,-z,x)`，再重排为 `(x,-z,y)` | `R` 的第 2/3 列取负 |
| E6 | Euler（列向量法） | 同 E5 | 直接用 `camera_target_pos=(y,-z,x)` | 不额外取负 |
| E7 | Euler（列向量法） | 同 E5 | 直接用 `(x,y,z)` | 不额外取负 |
| E8 | Euler（列向量法） | `yaw` 取负；UE→CV（`M_to_GL` 与 `M_T`） | `t = (x, z, -y)` | 不额外取负 |
| E9 | Euler（列向量法） | `pitch/yaw` 取负；UE→CV；写入时对部分轴取负 | 平移先重排，再以 `(t0, t2, t1)` 写入；`scale=1.3333` | 第 1/2 行第 3 列取负，第三行前两列取负 |
| E10 | Euler（自定义） | 仅用 `Rx(pitch)` 与 `Ry(yaw)`；`R_ue` 部分元素手动取负；再用特殊 `M_UE_to_CV_T` | `t = (y, z, x) * 0.01` | 不额外取负 |
| E11 | Euler（自定义） | 参数重排：`Rx(pitch) * Ry(yaw) * Rz(roll)`；不做 UE→CV 转换 | `t = (x, y, z)` | 直接输出 `R_ue` |
| M1 | Matrix | `R` 由 `camera_marix` 三列重组 | `t = (x, y, z)` | 写入时 X/Z 列取负（翻转 X/Z 轴） |
| M2 | Matrix | `R = F * c2w * F`，`F=diag(1,1,-1)`（翻转 Z 轴） | `t = (x, y, -z) * scale` | 不额外取负 |
| M3 | Matrix | `R = c2w` 直接使用 | `t = (x, y, z)` | 不额外取负 |

## 逻辑对应游戏

**E1**（Python-rot + UE→CV，`(y,-z,x)` 平移，输出列 2/3 取负）
规模差异：`scale=0.01`、`0.1`、`1.0`、`0.02`；部分游戏强制 `roll=0`。
`scale=0.01`：BatmanAK, BlackMythWukong, Borderlands3, Borderlands4, FinalFantasy7, HogwartsLegacy, Infused, Palworld, ReadyOrNot, AtomicHeart, SilentHill2, SilentHillF, Ghostrunner, Ghostrunner2。
`scale=0.1`：SandFall, Stray。
`scale=1.0`：GodofWar5, GodofWar5_CE, RatchetClankRiftApart。
`scale=0.02`：Hi-Fi-RUSH。
其中 `roll=0`：AtomicHeart, SilentHill2, SilentHillF, Ghostrunner, Ghostrunner2。

**E2**（`pitch/yaw` 取负，`(x,-y,-z)` 平移，输出列 2/3 取负）
游戏：ResidentEvils3, ROTTR（Euler 重载）。

**E3**（`pitch/roll` 取负，平移 `(x,y,z)`，不额外取负）
游戏：DevilMayCry5, ResidentEvil2。

**E4**（Euler 参数顺序交换，平移 `(x,-z,y)`，输出列 2/3 取负）
游戏：Witcher3, Witcher3CE。

**E5**（列向量法，平移 `(x,-z,y)`，输出列 2/3 取负）
游戏：AssassinsCreedOdyssey, AssassinsCreedOrigin, AssassinsCreedShadows, AssassinsCreedValhalla, DarkSoulsIII, ImmortalsFenyxRising（`roll=0`）。

**E6**（列向量法，平移 `(y,-z,x)`，不额外取负）
游戏：Spider-Man（Euler 重载）。

**E7**（列向量法，平移 `(x,y,z)`，不额外取负）
游戏：EldenRing（Euler 重载）。

**E8**（列向量法，`yaw` 取负，平移 `(x,z,-y)`，不额外取负）
游戏：DeathStrandingDirectorsCut。

**E9**（列向量法，`pitch/yaw` 取负，平移分量写入顺序为 `(t0,t2,t1)`，部分轴取负）
游戏：Sekiro。

**E10**（自定义 `Rx/Ry`，手动翻转 `R_ue` 部分元素，平移 `(y,z,x)`）
游戏：HorizonForbiddenWest。

**E11**（自定义 Euler 重排，无 UE→CV 变换，平移 `(x,y,z)`）
游戏：GodOfWar（Euler 重载）。

**M1**（Matrix 输入，X/Z 列取负）
游戏：MilesMorales, Spider-Man（Matrix 重载）。

**M2**（Matrix 输入，`R = F*c2w*F`，平移 `z` 取负）
游戏：EldenRing（Matrix 重载，`scale=1.0`）, ROTTR（Matrix 重载，`scale=1.25`）。

**M3**（Matrix 输入直接使用）
游戏：GodOfWar（Matrix 重载）。

备注：部分游戏同时有 Euler 与 Matrix 的重载（如 `EldenRing`、`ROTTR`、`Spider-Man`、`GodOfWar`），所以会在多个逻辑中出现。
