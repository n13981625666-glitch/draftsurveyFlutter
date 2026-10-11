# ships-lib/ — 加密后的船舶档案库

这里放所有船的 `<船舶ID>.shipx`（AES-256-GCM 密文，可以提交到仓库）。由 `npm run pack-ship` 生成。

构建时用 `node tools/select-ship.mjs <船舶ID>` 选出**一条**船，把它复制到 `src/ships/`（该目录是生成的，不提交），
程序里就只有这一条船。见仓库根目录 README 的"多船"一节。
