# 素材来源

`source-sheets/` 存放正式关键帧创作中使用的源图，`prompts/` 存放其对应提示词。`provenance.json` 用仓库相对路径登记每张源图和提示词的 SHA-256，并记录关键单格的来源关系。档案包含15张源图、13份原始提示词；两张源图没有单独保存的提示词，已如实标记。

多格源图中的其他格不自动视为最终动画帧。运行时使用的 PNG 以 `../verification/runtime-resource-allowlist.json` 和关键帧锚点文件为准；来源图、提示词和编辑元数据不随 `.app` 打包。F13伸展使用 `frieren-stretch-source-v2.png` 四格，提取和统一锚点记录在 `provenance/frieren-stretch-v2-metadata.json`；四帧共用缩放，画布为512×704，原画主体高度490 px，脚底Y=672、躯干根部X=266。旧的芙莉莲坐姿/伸展源图只为 sit-0..3 提供素材。

Himmel look/point v3 源图上排零基第 0、1、2 列提供 look-0/1/2；上排第 3 列未用；下排四格提供 point-0..3。D03 的 Himmel `look-3` 仅使用 downlook edit 的底行零基第 1 列（第二格），其余七格未用。
