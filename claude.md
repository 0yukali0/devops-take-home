# 確保以下地端測試通過
1. make migration-test
2. make e2e-test
3. make lint

# 確保github action通過
act為地端github action測試工具，act push跑全部測試
1. act push