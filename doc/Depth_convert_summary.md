# `convert_to_physical_distance_depth_u64` 深度转换逻辑分类（gcv_games）

统计：当前 `gcv_games` 里共有 60 个实现，按逻辑归为 16 类。

## 逻辑概览表

| ID | 深度输入解释 | 处理/公式类型 | 关键参数 | 代表游戏 |
|---|---|---|---|---|
| D1 | `depthval` 低 32 位按 `float` 解释 | 透视逆变换（near/far 反推） | `n=0.1`, `f=10000` | AssassinsCreedOdyssey 等 32 个 |
| D2 | `float` | 透视逆变换 | `n=0.01`, `f=10000` | AtomicHeart, Ghostrunner, Ghostrunner2 |
| D3 | `float` | 透视逆变换 | `n=0.001`, `f=10000` | ReadyOrNot |
| D4 | `float` | 透视逆变换 | `n=0.15`, `f=10003.814` | GTAV, RDR2 |
| D5 | `float` | 透视逆变换（先 `depth=1-depth` 反转） | `n=0.1`, `f=10000` | BatmanAK, Spider-Man |
| D6 | `float` | 透视逆变换（near/far 动态） | `n=NEAR_PLANE_DISTANCE`, `f=g_far_plane_distance` | CrysisRemastered |
| D7 | `float` | 近远裁剪线性化（`near / (1 - z*(1 - near/far))`） | `n=0.1`, `f=g_far_plane_distance` | Crysis2, NoMansSky |
| D8 | `uint24` 归一化 | 近远裁剪线性化 | `n=0.1`, `f=g_far_plane_distance` | Crysis3, CrysisGOG |
| D9 | `uint24` 归一化 | 近远裁剪线性化 | `n=0.1`, `f=FAR_PLANE_DISTANCE` | Crysis |
| D10 | `uint32` 归一化 | 曲线拟合（指数/对数型） | `1.28/(0.000077579959 + exp(..))` | Cyberpunk2077, Cyberpunk2026 |
| D11 | `uint32` 归一化 | 曲线拟合（指数/对数型） | `1.28/(0.0004253421645 + exp(..))` | GodOfWar, ROTTR, RE 系 |
| D12 | `uint24` 归一化 | 有理函数拟合 | `5415.69378002/(1 + 541167.20430436*z)` | DishonoredDOTO |
| D13 | `uint30` 归一化 | 有理函数拟合 | `0.00310475/(1 - 1.00787427*z)` | Control |
| D14 | `uint30` 归一化 | 有理函数拟合 | `0.00313259/(1 - 1.00787352*z)` | HorizonZeroDawn |
| D15 | `uint24` 归一化 | 线性深度 | `near=1`, `far=1000` | EuroTruckSimulator2, MicrosoftFlightSimulator2024 |
| D16 | `uint32` 归一化（反转） | 线性深度 | `near=1`, `far=50000`, `z=1-depth` | MicrosoftFlightSimulator2020 |

说明：D11 覆盖该组曲线拟合常量对应的所有游戏（避免重复编号）。

## 详细分类与对应游戏

**D1**
- 处理逻辑：`depthval` 低 32 位按 `float` 解码，使用标准透视逆变换 `z = A / (depth - B)`。
- 关键参数：`n=0.1`, `f=10000`。
- 游戏：AssassinsCreedOdyssey, AssassinsCreedOrigin, AssassinsCreedShadows, AssassinsCreedValhalla, BlackMythWukong, Borderlands3, Borderlands4, DarkSoulsIII, DeathStrandingDirectorsCut, DevilMayCry5, EldenRing, FinalFantasy7, GodofWar5, GodofWar5_CE, Hi-Fi-RUSH, HogwartsLegacy, HorizonForbiddenWest, ImmortalsFenyxRising, Infused, MilesMorales, Palworld, RatchetClankRiftApart, ResidentEvil2, RoR2, SandFall, Sekiro, Shipbreaker, SilentHill2, SilentHillF, Stray, Witcher3, Witcher3CE。

**D2**
- 处理逻辑：同 D1，但 `n=0.01`。
- 游戏：AtomicHeart, Ghostrunner, Ghostrunner2。

**D3**
- 处理逻辑：同 D1，但 `n=0.001`。
- 游戏：ReadyOrNot。

**D4**
- 处理逻辑：同 D1，但 `n=0.15`, `f=10003.814`。
- 游戏：GTAV, RDR2。

**D5**
- 处理逻辑：`float` 解码后先反转 `depth = 1 - depth`，再用 D1 的透视逆变换。
- 游戏：BatmanAK, Spider-Man。

**D6**
- 处理逻辑：`float` 解码后，用动态的 `near/far` 做标准透视逆变换。
- 关键参数：`n=NEAR_PLANE_DISTANCE`, `f=g_far_plane_distance`。
- 游戏：CrysisRemastered。

**D7**
- 处理逻辑：`float` 解码后，使用 `near / (1 - z*(1 - near/far))` 线性化。
- 关键参数：`n=0.1`, `f=g_far_plane_distance`。
- 游戏：Crysis2, NoMansSky。

**D8**
- 处理逻辑：`depthval / 16777215`（24 位归一化）后用 D7 公式。
- 关键参数：`n=0.1`, `f=g_far_plane_distance`。
- 游戏：Crysis3, CrysisGOG。

**D9**
- 处理逻辑：`depthval / 16777215` 后用 D7 公式，但 `far` 为固定常量。
- 关键参数：`n=0.1`, `f=FAR_PLANE_DISTANCE`。
- 游戏：Crysis。

**D10**
- 处理逻辑：`depthval / 4294967295` 归一化后用指数/对数拟合曲线。
- 关键参数：`1.28/(0.000077579959 + exp_fast_approx(354.9329993 * z - 83.84035513))`。
- 游戏：Cyberpunk2077, Cyberpunk2026。

**D11**
- 处理逻辑：`depthval / 4294967295` 归一化后用指数/对数拟合曲线。
- 关键参数：`1.28/(0.0004253421645545 + exp_fast_approx(354.8489261773826 * z - 83.12790960252826))`。
- 游戏：GodOfWar, ROTTR, ResidentEvil8, ResidentEvils, ResidentEvils2, ResidentEvils3。

**D12**
- 处理逻辑：`depthval / 16777215` 归一化后用有理函数拟合。
- 关键参数：`5415.69378002 / (1.0 + 541167.20430436 * z)`。
- 游戏：DishonoredDOTO。

**D13**
- 处理逻辑：`depthval / 1073741824`（30 位归一化）后用有理函数拟合。
- 关键参数：`0.00310475 / (1.0 - 1.00787427 * z)`。
- 游戏：Control。

**D14**
- 处理逻辑：`depthval / 1073741824`（30 位归一化）后用有理函数拟合。
- 关键参数：`0.00313259 / (1.0 - 1.00787352 * z)`。
- 游戏：HorizonZeroDawn。

**D15**
- 处理逻辑：`depthval / 16777215` 归一化后用标准线性深度公式。
- 关键参数：`near=1`, `far=1000`。
- 游戏：EuroTruckSimulator2, MicrosoftFlightSimulator2024。

**D16**
- 处理逻辑：`z = 1 - depthval/4294967295`（反转 32 位深度）后用标准线性深度公式。
- 关键参数：`near=1`, `far=50000`。
- 游戏：MicrosoftFlightSimulator2020。

备注：同一游戏若存在多个版本文件（如 `ResidentEvils*`），按文件名列出。
