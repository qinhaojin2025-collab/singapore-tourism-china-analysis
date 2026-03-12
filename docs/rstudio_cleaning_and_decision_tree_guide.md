# RStudio 数据清洗与决策树分析说明

## 1. 参考结构

这套脚本的组织方式参考了你给出的两个页面：

- 数据清理思路参考：[Habari Tanzania - Data Preparation](https://habaritanzania.netlify.app/dataprep/dataprep)
- 决策树流程参考：[Habari Tanzania - Decision Tree Analysis](https://habaritanzania.netlify.app/analysis/decision_tree)

我沿用了它们的基本顺序：

1. 先加载包
2. 再导入数据
3. 先做清理和变量构造
4. 再做模型准备
5. 最后做决策树、可视化和评估

但我没有照抄它们的字段设计，因为你的数据是“单国家月度时间序列”，而不是“游客明细调查数据”。

## 2. 需要的 pacman 包

### 2.1 数据清理脚本需要的包

在 `scripts/tourism_data_prep_rstudio.R` 中使用：

- `tidyverse`
- `readxl`
- `lubridate`
- `writexl`
- `here`

这些包的作用分别是：

- `tidyverse`：数据清洗、变形和导出
- `readxl`：读取原始 Excel
- `lubridate`：处理日期
- `writexl`：导出清洗后的 Excel
- `here`：稳定定位项目路径

### 2.2 决策树脚本需要的包

在 `scripts/tourism_decision_tree_rstudio.R` 中使用：

- `tidyverse`
- `here`
- `rpart`
- `rpart.plot`
- `caret`
- `yardstick`
- `patchwork`

这些包的作用分别是：

- `rpart`：建立决策树模型
- `rpart.plot`：绘制决策树图
- `caret`：生成混淆矩阵和常见评估结果
- `yardstick`：补充模型评估
- `patchwork`：后续如果要拼图，会更方便

## 3. 为什么这样清洗

### 3.1 跳过前 29 行

原始 Excel 前 29 行是元数据，不是逐月观测值。如果直接读入，这些说明行会破坏字段类型，因此必须跳过。

### 3.2 删除 2015-12-01

这条记录在月度核心变量上基本都是空值，无法支持 EDA、CDA、聚类和决策树，因此删除比插值更合理。

### 3.3 保留年度变量但不做月度插补

`spend_per_capita`、`tourism_receipts`、`avg_stay_annual` 本来就是年度变量。强行把它们填到每个月，会把年度信息伪装成月度信息，所以这里只保留、不扩展。

### 3.4 新增 `china_share`

光看中国游客人数，只能看到“规模”；加入 `china_share` 后，才能解释“中国市场在整体旅游中的权重变化”，这对聚类和决策树都更有价值。

### 3.5 对 `avg_stay_monthly` 做高端截尾

疫情阶段的逗留时间出现明显极端值。它们不一定是错的，但会让聚类和决策树过度围绕少数极端月份分裂，所以保留原始列，同时新增 `avg_stay_monthly_capped` 作为建模列。

### 3.6 生成聚类和决策树专用字段

为了让一份数据同时服务 4 个模块，我在最终表中额外准备了：

- 聚类专用标准化列 `cluster_z_*`
- 决策树目标变量 `hotel_occ_level_tertile`
- 决策树业务版目标变量 `hotel_occ_level_business`
- 时间顺序训练测试划分 `dataset_split`

## 4. 决策树的推荐流程

### 4.1 目标变量

推荐主模型使用：

- `hotel_occ_level_tertile`

原因是三类样本更均衡，更适合课堂展示。

### 4.2 自变量

推荐先用这几个：

- `visitor_arrivals`
- `china_share`
- `avg_stay_monthly_capped`
- `month`

原因是：

- `visitor_arrivals` 代表市场总体规模
- `china_share` 代表中国市场结构
- `avg_stay_monthly_capped` 代表停留行为
- `month` 代表季节性

### 4.3 为什么不用年度变量

因为年度变量和目标变量频率不一致，而且有效观测太少，放进月度分类树会降低模型可信度。

### 4.4 为什么按时间切分训练测试集

你的数据是时间序列。如果随机切分，未来月份的信息可能会提前泄漏给训练集。按时间切分更符合真实预测逻辑。

### 4.5 为什么要剪枝

原始树通常会长得太复杂。参考决策树页面的思路，建树后再根据交叉验证误差选择最佳 `cp` 做剪枝，能提高可解释性并减少过拟合。

## 5. 在 RStudio 中的执行顺序

建议按下面顺序运行：

1. 先运行 `scripts/tourism_data_prep_rstudio.R`
2. 确认 `data/processed/` 中已经生成清洗后文件
3. 再运行 `scripts/tourism_decision_tree_rstudio.R`
4. 到 `outputs/` 查看结果：
   - `decision_tree_plot.png`
   - `decision_tree_metrics.csv`
   - `decision_tree_confusion_matrix.csv`
   - `decision_tree_variable_importance.csv`
   - `decision_tree_test_predictions.csv`

## 6. 最终建议

如果你写课程作业，我建议这样安排：

- 数据清理部分：重点写“跳过元数据、保留月度主变量、新增占比和阶段变量、处理极端值”
- 决策树部分：重点写“用旅游规模、中国市场权重、逗留时间和季节性解释酒店入住率状态”

这样既贴合参考网站的流程，也更符合你这份数据本身的结构。
