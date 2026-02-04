# c2w 输出结构与坐标转换总结（gcv_games + mod_scripts）

本文总结 `gcv_games` 与 `mod_scripts` 两条来源最终生成的 `c2w`（camera-to-world）矩阵形态、旋转元素含义、常见计算公式与平移重排规律。

## 1. c2w 的统一结构

`c2w` 在本仓库中统一为 **3x4 行主序**（row-major）矩阵，存放在 `CamMatrixData::extrinsic_cam2world`。

```text
c2w = [ r_x  u_x  f_x  t_x
        r_y  u_y  f_y  t_y
        r_z  u_z  f_z  t_z ]
```

含义：
- 第 0 列 `r` 是相机坐标系 +X 轴（Right）在世界坐标系中的方向。
- 第 1 列 `u` 是相机坐标系 +Y 轴（Up 或 Down，取决于约定）在世界坐标系中的方向。
- 第 2 列 `f` 是相机坐标系 +Z 轴（Forward 或 Backward，取决于约定）在世界坐标系中的方向。
- 第 3 列 `t` 是相机在世界坐标系中的位置。

这也是 `mod_scripts` 里写入 `contiguousmembuf` / shared memory 时采用的布局，`gcv_utils::cam_matrix_from_flattened_row_major_buffer` 直接按行主序读取。

## 2. 旋转矩阵元素的通用含义

以 `mat = c2w[:3,:3]` 表示旋转部分（3x3），则：
- `mat[0][0]` 是相机 X 轴在世界 X 方向的分量。
- `mat[1][0]` 是相机 X 轴在世界 Y 方向的分量。
- `mat[2][0]` 是相机 X 轴在世界 Z 方向的分量。
- `mat[0][1]` 是相机 Y 轴在世界 X 方向的分量。
- 依此类推。

一句话：**列 = 相机轴，行 = 世界分量**。

## 3. 常见 Euler → R 的计算公式（gcv_games 中最常见模板）

gcv_games 中最常见的是用 `roll/pitch/yaw` 构造 `R_ue` 或直接构造列向量 `right/up/forward`。常用的列向量公式如下：

设：
`cr=cos(roll)`, `sr=sin(roll)`, `cp=cos(pitch)`, `sp=sin(pitch)`, `cy=cos(yaw)`, `sy=sin(yaw)`。

```text
right   = ( cy*cp,         -sy*cp,          sp )
up      = ( cy*sp*sr+sy*cr, -sy*sp*sr+cy*cr, -cp*sr )
forward = ( -cy*sp*cr+sy*sr, sy*sp*cr+cy*sr,  cp*cr )
```

因此旋转矩阵为：

```text
R = [ cy*cp,  cy*sp*sr+sy*cr,  -cy*sp*cr+sy*sr
      -sy*cp, -sy*sp*sr+cy*cr,  sy*sp*cr+cy*sr
       sp,    -cp*sr,           cp*cr ]
```

这套公式覆盖了 **E5/E6/E7/E8/E9** 这一类逻辑（见 `IGCS_process_camera_buffer_summary.md`）。

### 3.1 UE → CV 轴映射后的矩阵

很多 IGCS 逻辑都会做 UE→CV 轴映射：

```text
(x, y, z)_UE  →  (y, -z, x)_CV
```

它对任意列向量 `v=(vx,vy,vz)` 的作用是：

```text
v' = (vy, -vz, vx)
```

所以如果 `R` 的列为 `right/up/forward`，则映射后为：

```text
right'   = ( right.y,   -right.z,   right.x )
up'      = ( up.y,      -up.z,      up.x )
forward' = ( forward.y, -forward.z, forward.x )
```

再叠加代码中常见的“列取负”（例如写入时 `-R[?][1]`, `-R[?][2]`），相当于：

```text
right_out = right'
up_out    = -up'
forward_out = -forward'
```

这解释了为什么一些游戏里旋转矩阵会出现整体“列反号”的现象，而 **平移仍保持 UE→CV 的分量重排**。

### 3.2 ETS2 SDK 的显式矩阵公式（示例包含 `-sin(pitch)`）

`mod_scripts/EuroTruckSimulator2_SCS_SDK.cpp` 明确给出了欧拉到矩阵的行主序公式：

```text
R = [ cos_h*cos_r + sin_h*sin_p*sin_r,  -cos_h*sin_r + sin_h*sin_p*sin_r,  sin_h*cos_p
      cos_p*sin_r,                     cos_p*cos_r,                     -sin_p
      -sin_h*cos_r + cos_h*sin_p*sin_r, sin_h*sin_r + cos_h*sin_p*cos_r,  cos_h*cos_p ]
```

这里 `h=heading`, `p=pitch`, `r=roll`。可以看到 `R[1][2] = -sin(pitch)`（0-based 行列）。如果你使用 1-based 索引记为 `mat[2][3]`，容易和“mat[2][2]”混淆。

### 3.3 `edit_json.py` 的 UE→OpenGL 旋转公式（你当前的校验基准）

`python_threedee/_jake/edit_json.py` 中的 `_rotation_matrix_from_euler_angles_ue_to_opengl(yaw, pitch, roll)` 先计算一组中间量：

设：
`cy=cos(yaw)`, `sy=sin(yaw)`, `cp=cos(pitch)`, `sp=sin(pitch)`, `cr=cos(roll)`, `sr=sin(roll)`。

```text
r00 = cy*cr - sy*sp*sr
r01 = -sy*cp
r02 = cy*sr + sy*sp*cr
r10 = sy*cr + cy*sp*sr
r11 = cy*cp
r12 = sy*sr - cy*sp*cr
r20 = -cp*sr
r21 = sp
r22 = cp*cr
```

函数返回的是 **重排+取负后的行主序 3x3**（OpenGL 坐标）：

```text
R_gl = [ r00,  r02, -r01
         r10,  r12, -r11
         r20,  r22, -r21 ]
```

因此最终矩阵元素可直接写成：

```text
mat[0][0] =  cy*cr - sy*sp*sr
mat[0][1] =  cy*sr + sy*sp*cr
mat[0][2] =  sy*cp
mat[1][0] =  sy*cr + cy*sp*sr
mat[1][1] =  sy*sr - cy*sp*cr
mat[1][2] = -cy*cp
mat[2][0] = -cp*sr
mat[2][1] =  cp*cr
mat[2][2] = -sp
```

这就是你用来校验的结论来源：  
**`mat[2][2] = -sp = -sin(pitch)`**（0-based 索引）。  
如果你用 1-based 索引写法，那就是 `mat[3][3] = -sin(pitch)`。

另外注意 `edit_json.py` 写入 JSON 时的行主序位置对应关系：
- `extrinsic[0..2]` → `row0 col0..2`
- `extrinsic[4..6]` → `row1 col0..2`
- `extrinsic[8..10]` → `row2 col0..2`

它只覆盖 `extrinsic_cam2world` 的 **旋转部分**（平移不改）。

### 3.4 对照表：`edit_json` 与 IGCS 常见模板的“pitch 指标”

下表用于快速判断“哪个元素最适合盯着看 pitch 的单调变化”。  
注意：不同流水线处于不同坐标系，必须先保证你比较的是 **同一坐标系** 的旋转矩阵。

| 流水线/模板 | 旋转来源 | pitch 相关的显式元素（0-based） | 说明 |
|---|---|---|---|
| `edit_json.py` `_rotation_matrix_from_euler_angles_ue_to_opengl` | 明确公式（3.3） | `mat[2][2] = -sin(pitch)` | 你当前的校验基准 |
| ETS2 SDK (`EuroTruckSimulator2_SCS_SDK.cpp`) | 明确公式（3.2） | `mat[1][2] = -sin(pitch)` | 行主序公式直接给出 |
| IGCS 常见 E1/E5（right/up/forward + UE→CV + 列 1/2 取负） | 右/上/前列向量公式（3.0） | `mat[1][2] = cos(pitch) * cos(roll)` | 若 `roll≈0`，可近似用 `mat[1][2]≈cos(pitch)` |

如果你希望用 `mat[2][2]` 做单调性检测：  
只有 **`edit_json` 这套 OpenGL 旋转公式**可以保证 `mat[2][2] = -sin(pitch)`。  
IGCS E1/E5 模板下，`mat[2][2]` 是 `-forward.x`，它会同时受 `yaw` 与 `roll` 影响，因此不适合直接当 pitch 单调指标。

## 4. 平移的规律（为什么有时需要调换位置）

平移向量 `t` 表示 **相机位置在世界坐标系的坐标**。它是否需要调换位置，取决于你对“世界坐标系”的改动类型：

规则 A：如果你**改变了世界坐标系的轴定义**（例如 UE→CV），那么平移也必须按同样的轴映射处理：

```text
t' = M * t
```

规则 B：如果你只是对“相机坐标系”做了轴翻转（例如只把列 1/2 取负），世界坐标系没变，那么平移通常 **不变**。

这两条规则解释了“有时翻、有时不翻”的现象。以下是实际代码中的常见平移重排模式：

| 归类 | 平移重排 | 典型来源 | 备注 |
|---|---|---|---|
| T1 | `(y, -z, x)` | gcv_games 中 E1 族 | UE→CV 轴映射的直接结果 |
| T2 | `(x, -z, y)` | Witcher3、REFramework 脚本 | 常见的 `x, -z, y` 交换 |
| T3 | `(x, y, z)` | EldenRing(Euler)、Unity 脚本 | 无世界轴变换 |
| T4 | `(x, z, -y)` | DeathStrandingDirectorsCut | 特殊 GL/相机约定 |
| T5 | `(y, z, x)` | HorizonForbiddenWest | 特殊 UE 变体 |
| T6 | `(x, -y, -z)` | GTA 脚本（再带缩放） | 先左手转右手，再 OpenCV/Open3D |

注意：**列取负 ≠ 平移取负**。列取负表示在“相机轴”上做镜像，平移是否取负取决于你是否同时改变了世界轴的意义。

## 5. python_threedee 对 `c2w` 的消费方式（影响你如何判矩阵正确）

`python_threedee` 里对 `extrinsic_cam2world` 的使用方式，会直接影响“矩阵是否正确”的判断标准：

- `python_threedee/poses.py` 与 `python_threedee/load_point_cloud_ue.py` 都把 `c2w[:3,:3]` 当成旋转、`c2w[:3,3]` 当成平移。  
- `poses.py` 在可视化时 **按列取相机轴**：`camera_x_dirs = c2ws[:,:3,0]`，`camera_y_dirs = c2ws[:,:3,1]`，`camera_z_dirs = c2ws[:,:3,2]`。  
这与本文“列=相机轴、行=世界分量”的约定一致。

另外 `load_point_cloud_ue.py` 当前使用的是 `cam2world_to_cv_unchanged`，意味着：  
**它假设 JSON 里的 `extrinsic_cam2world` 已经是目标坐标系，不再做 UE→CV 的轴映射**。  
如果你的 `extrinsic_cam2world` 仍是 UE 坐标，你必须先做轴映射或在导出脚本里完成，否则 `poses.py`/点云的方向会错。

## 6. mod_scripts 中的主要 c2w 生成方式

以下是 `mod_scripts` 中能直接观察到的几类做法，均最终写成 3x4 行主序矩阵：

| 来源脚本 | 旋转处理 | 平移处理 | 说明 |
|---|---|---|---|
| `cyberpunk2077_cyberenginetweaks_mod_init.lua` | `X=原X, Y=原Z, Z=-原Y` | 平移不变 | 只改旋转轴，平移未映射 |
| `residentevil_read_camera_matrix_transfcoords.lua` / `gcv_re8_camera_export_v1.0.lua` / `RE2/gcv_re2_camera_export_v2.0.lua` | 从 `WorldMatrix` 列向量重排并加符号 | `t = (x, -z, y)` | REFramework 通用变换 |
| `EuroTruckSimulator2_SCS_SDK.cpp` | 显式欧拉公式（见 3.2） | `t = (x, y, z)` | 使用 SCS 车身/头部坐标叠加 |
| `RoR2.cs` / `Shipbreaker.cs` | Unity `Matrix4x4.Rotate`，写出时列 1/2 取负 | `t = (x, y, z)` | 典型 Unity 方案 |
| `gtav_camera.cs` | 自建欧拉矩阵 + 多次轴翻转 | `t = (x, -y, -z) * 3` | 额外尺度与坐标系调整 |
| `RDR2_camera.cs` | 自建欧拉矩阵 | `t = (x, y, z)` | 无额外翻转 |

## 7. 结论：最终 c2w 的“长相”

无论来自 IGCS 还是 mod_scripts，最终 `c2w` 都是 **3x4 行主序**，列表示相机局部轴，行表示世界轴分量。旋转公式最常见的是 `right/up/forward` 的列向量公式（第 3 节），其后可能应用：
- UE→CV 的轴映射 `(x,y,z)->(y,-z,x)`。
- 列 1/2 取负（相机轴镜像，通常不动平移）。
- 翻转或交换平移分量（当“世界轴定义”被改变时）。

如果你手里有具体游戏或脚本的 `roll/pitch/yaw` 与最终矩阵数据，我可以按这份规则直接反推 `mat[i][j]` 的明确公式与翻转顺序。
