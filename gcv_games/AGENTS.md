经过我的测试，我发现不需要对reshade_shaders\DepthCapture.fx中的ReShade::DepthBuffer再进行处理，我已经将DepthCapture.fx修改妥当；

此外，我发现gcv_games\Cyberpunk2077.cpp中的depthval并不是将shader的float深度乘以 4294967295.0，将depthval通过如下的方式转换之后就是shader的float深度：
```cpp
	  uint32_t depth_as_u32 = static_cast<uint32_t>(depthval);
    float depth;
    std::memcpy(&depth, &depth_as_u32, sizeof(float));
```
因此gcv_reshade\copy_texture_into_packedbuf.cpp中的逻辑应该是将上面的反一下，将shader的float深度通过memcpy转为uint32（我理解的是这样，不确定对不对），然后就可以作为depthval传入convert_to_physical_distance_depth_u64了
<!-- 非常好，目前能够输出得到深度的npy文件了；但是线性深度无法直接用于重建场景（无法和c2w中的transltion对应，translation是以metre为尺度的）；
以赛博朋克2077为例（游戏类对应gcv_games\Cyberpunk2077.cpp和.h），它有一个convert_to_physical_distance_depth_u64函数，负责将原始深度缓存区的depthval转化为真实尺度（以metre为单位），不同游戏的深度转化函数不一定相同，均定义于各自游戏类中的convert_to_physical_distance_depth_u64函数中；

当前新的pipeline从reshade中得到的深度是看起来是来自于ReShade::GetLinearizedDepth?我看到reshade-shaders\Shaders\DisplayDepth.fx中有ReShade::DepthBuffer，这个变量和convert_to_physical_distance_depth_u64中的depthval是同一个数值吗？能否使用类似convert_to_physical_distance_depth_u64的方法来得到真实尺度的深度图呢？或者你有什么办法能够将当前的深度（看起来是归一化的线性深度？我不确定，只知道npy文件float数值都在0到1之间，且我利用单帧的RGB、相机外参.json、当前的归一化深度重建出来的点云看起来结构是正常的，但是多帧重建时深度的尺度不对导致点云无法对齐） -->

<!-- 新增.fx之后是否需要在游戏内reshade菜单enable新的.fx文件，是否会影响addon的RGB采集（displaydept     
  h.fx打开时屏幕画面会被法线图和深度图覆盖导致F11和F9/F10采集到的图片/视频数据不是原始的RGB）  

因为我需要编译项目生成.addon文件，最好检查一下编译依赖是否满足（实际在re8.exe游戏文件夹安装的是reshade6.4.0）

我再确认一下，游戏内按下F11后，截取单帧的RGB、meta.json以及depth.npy（只截取一帧，而且depth使用新的获取方法）；按下F9开启录制模式，按照原本的采集pipeline在采集RGB和.json的同时采集当前帧的depth（尽可能融入到原本的pipeline中，而不是各采集各的不同步） -->

<!-- 1. 我需要在visual studio中编译，因此最好帮我把项目文件的依赖和include目录也补充上（先检查一下是否需要补充，需要补充的话再修改）（可能是修改gcv_reshade\gcv_reshade.vcxproj和gcv_reshade\gcv_reshade.vcxproj.filters，你自己研究一下），以确保我能够直接编译成功项目；
2. 这个新的pipeline只适用于单帧截取吗，还是也适用于F9/F10的视频录制模式？
3. 这个新的pipeline必须要Enable DisplayDepth.fx才能正常跑通吗，因为我还需要视频数据，开着DisplayDepth.fx时整个画面会失真（左半屏是法线图、右半屏是深度图），我希望视频数据和深度数据能够同时正确采集。 -->

<!-- 先向你介绍当前reshade_cv项目的pipeline：visual studio2022中编译当前项目会生成reshade_cv.addon文件，针对游戏安装reshade6.4.0之后，会在游戏执行文件同目录(D:\SteamLibrary\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE)生成reshade-shaders文件夹（我已经将这个文件夹复制到了当前项目文件夹./reshade-shaders），将编译后的reshade_cv.addon放入，在游戏内就可以通过F11来单帧采集、F9/F10来开始/结束视频采集，视频采集会在cv_saved中生成一个文件夹，其中每一帧对应一个.json和.npy，.json中存储相机c2w矩阵、fov、画面长宽等，.npy则是深度图，再将录制的视频ffmpeg拆为单帧的jpg，也即每一帧有三个文件（json/npy/jpg），可以调用项目文件夹下的`python_threedee\_jake\run_pipeline.py`来重建出点云。

目前的问题：游戏内按下home键打开reshade6.4.0的菜单，勾选displaydepth.fx之后就可以看到游戏实时的法线图和深度图，但是当前reshade_cv项目无法直接读取到dx12以及vulkan游戏引擎的深度缓冲（虽然不管哪种引擎都能够在打开displaydepth.fx之后看到深度图），因此cv_saved下面采集到的.npy文件无效的深度图，
displaydepth.fx的脚本代码在reshade-shaders\Shaders\DisplayDepth.fx，能否在当前reshade_cv的pipeline中集成displaydepth.fx的方法来获取到深度图？ -->


<!-- 对不起我弄错了，ResidentEvil2.cpp和.h是验证过走不通的游戏类（因为igcs connector存在问题，无法从igcs中拿到数值），应该参照`gcv_games\ResidentEvils.cpp`和`gcv_games\ResidentEvils.h`来编写游戏类；以及mod_scripts\RE2\gcv_re2_camera_export_v2.0.lua是未经测试的脚本，mod_scripts\residentevil_read_camera_matrix_transfcoords.lua是经过测试的正确脚本，re8的脚本最好参照测试过的脚本来写 -->

<!-- 我想要编写生化危机8村庄的采集脚本，之前已经验证过生化危机2的游戏类和脚本是正确的（参考`gcv_games\ResidentEvil2.cpp`、`gcv_games\ResidentEvil2`、`mod_scripts\residentevil_read_camera_matrix_transfcoords.lua`），我直接复制了ResidentEvil2.cpp和.h改名为了ResidentEvil8.cpp和.h，帮我修改ResidentEvil8.cpp和.h以便适用于生化危机8村庄，并编写合适的.lua脚本放在/mod_scrpts下 -->