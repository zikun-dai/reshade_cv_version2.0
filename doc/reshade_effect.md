- IgcsDof.fx：IGCS Connector 的景深(DoF)工作 shader（technique 叫 IgcsDOF），Connector 会在你开 DoF 会话时往里面的隐藏参数写值并驱动它出效果；只有你要用 Connector 的 DoF 功能时才需要勾选/启用 IgcsDOF（而且通常要求放在效果列表靠后/最底部）。

- IgcsSourceTester.fx：Uniform 测试/调试用，声明了一堆 IGCS_camera* 的 uniform（带 source="IGCS_..." 注解），启用 IgcsSourceTester 后会把相机数据/矩阵打印在屏幕上；不是正常使用 IgcsConnector 的必需项，一般只在你想确认数据是否在更新时临时勾选。

结论：不需要必须同时勾选这两个 effect。

- 只想“Connector 能连上/正常运行”：通常都不用勾。
- 想用 DoF：勾 IgcsDOF。
- 想看/验证 IGCS 相机 uniform：临时勾 IgcsSourceTester（看完可关）。