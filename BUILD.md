main分支是验证无误的commit；

如果有需要测试的功能（或者新增了功能，但是有bug还没调通）：

```bash
git switch -c wip/cp2077-new-feature
```
新分支下可以正常进行commit和push；


代码调通后merge回main分支：
```bash
git switch main
git pull --rebase origin main
git merge --no-ff wip/cp2077-new-feature
git push origin main
```


如果需要临时切换回之前的一次commit进行测试：
```bash
git switch --detach e571aa1853dd1a6e0b762be32f8a12e8fcf14db7
```
测试完之后直接放弃全部更改，然后：
```bash
git switch main
```