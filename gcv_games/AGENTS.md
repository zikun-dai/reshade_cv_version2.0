<!-- 1. 删掉reload_effect_next_frame是否会对整体的pipeline造成什么影响？
2. 我另外问了copilot，给出的回答如下：
```
修正说明：
•	原因：reshade::api::effect_runtime 没有 reload_effect_next_frame 成员函数。正确的 API 是 reload_effects()，用于重新加载所有效果文件。
•	修复方法：将 runtime->reload_effect_next_frame(kDepthFxFile); 替换为 runtime->reload_effects();。
•	这样可以保证效果文件会在下一帧被重新加载，符合 ReShade 5.8.0 的 API 设计。
如需只重载特定文件，需自行实现相关逻辑，但 ReShade 官方 API 只提供全量重载。
```
这个方法是否可行？ -->

<!-- 编译过程中遇到了问题：
使用的是visual studio2022的“生成解决方案”，Debug，x64；
出错位置在main.cpp的`runtime->reload_effect_next_frame(kDepthFxFile);`，代码上下文如下：
```cpp
    if (tech.handle == 0) {
        if (!shdata.depth_export_warned_missing_fx) {
            reshade::log_message(reshade::log_level::warning, "GcvDepthExport.fx missing or failed to compile");
            runtime->reload_effect_next_frame(kDepthFxFile);
            shdata.depth_export_warned_missing_fx = true;
        }
        return false;
    }
```
报错内容：
```bash
类 "reshade::api::effect_runtime" 没有成员 "reload_effect_next_frame"
```
应该如何解决？ -->

<!-- 1. 我需要在visual studio中编译，因此最好帮我把项目文件的依赖和include目录也补充上（先检查一下是否需要补充，需要补充的话再修改）（可能是修改gcv_reshade\gcv_reshade.vcxproj和gcv_reshade\gcv_reshade.vcxproj.filters，你自己研究一下），以确保我能够直接编译成功项目；
2. 这个新的pipeline只适用于单帧截取吗，还是也适用于F9/F10的视频录制模式？
3. 这个新的pipeline必须要Enable DisplayDepth.fx才能正常跑通吗，因为我还需要视频数据，开着DisplayDepth.fx时整个画面会失真（左半屏是法线图、右半屏是深度图），我希望视频数据和深度数据能够同时正确采集。 -->

<!-- 先向你介绍当前reshade_cv项目的pipeline：visual studio2022中编译当前项目会生成reshade_cv.addon文件，针对游戏安装reshade6.4.0之后，会在游戏执行文件同目录(D:\SteamLibrary\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE)生成reshade-shaders文件夹（我已经将这个文件夹复制到了当前项目文件夹./reshade-shaders），将编译后的reshade_cv.addon放入，在游戏内就可以通过F11来单帧采集、F9/F10来开始/结束视频采集，视频采集会在cv_saved中生成一个文件夹，其中每一帧对应一个.json和.npy，.json中存储相机c2w矩阵、fov、画面长宽等，.npy则是深度图，再将录制的视频ffmpeg拆为单帧的jpg，也即每一帧有三个文件（json/npy/jpg），可以调用项目文件夹下的`python_threedee\_jake\run_pipeline.py`来重建出点云。

目前的问题：游戏内按下home键打开reshade6.4.0的菜单，勾选displaydepth.fx之后就可以看到游戏实时的法线图和深度图，但是当前reshade_cv项目无法直接读取到dx12以及vulkan游戏引擎的深度缓冲（虽然不管哪种引擎都能够在打开displaydepth.fx之后看到深度图），因此cv_saved下面采集到的.npy文件无效的深度图，
displaydepth.fx的脚本代码在reshade-shaders\Shaders\DisplayDepth.fx，能否在当前reshade_cv的pipeline中集成displaydepth.fx的方法来获取到深度图？ -->


<!-- 对不起我弄错了，ResidentEvil2.cpp和.h是验证过走不通的游戏类（因为igcs connector存在问题，无法从igcs中拿到数值），应该参照`gcv_games\ResidentEvils.cpp`和`gcv_games\ResidentEvils.h`来编写游戏类；以及mod_scripts\RE2\gcv_re2_camera_export_v2.0.lua是未经测试的脚本，mod_scripts\residentevil_read_camera_matrix_transfcoords.lua是经过测试的正确脚本，re8的脚本最好参照测试过的脚本来写 -->

<!-- 我想要编写生化危机8村庄的采集脚本，之前已经验证过生化危机2的游戏类和脚本是正确的（参考`gcv_games\ResidentEvil2.cpp`、`gcv_games\ResidentEvil2`、`mod_scripts\residentevil_read_camera_matrix_transfcoords.lua`），我直接复制了ResidentEvil2.cpp和.h改名为了ResidentEvil8.cpp和.h，帮我修改ResidentEvil8.cpp和.h以便适用于生化危机8村庄，并编写合适的.lua脚本放在/mod_scrpts下 -->