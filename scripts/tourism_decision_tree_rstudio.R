if (!require("pacman")) install.packages("pacman")

pacman::p_load(
  tidyverse,
  here,
  rpart,
  rpart.plot,
  caret,
  yardstick,
  patchwork
)

data_path <- here::here("data", "processed", "tourism_four_part_analysis_ready.csv")
output_dir <- here::here("outputs")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

analysis_df <- readr::read_csv(data_path, show_col_types = FALSE) |>
  mutate(
    date = as.Date(date),
    period = factor(period, levels = c("pre_covid", "covid_shock", "recovery")),
    quarter = factor(quarter),
    month = factor(month),
    dataset_split = factor(dataset_split, levels = c("train", "test")),
    hotel_occ_level_tertile = factor(hotel_occ_level_tertile, levels = c("low", "medium", "high")),
    hotel_occ_level_business = factor(hotel_occ_level_business, levels = c("low", "medium", "high"))
  )

train_df <- analysis_df |>
  filter(dataset_split == "train")

test_df <- analysis_df |>
  filter(dataset_split == "test")

# Main classroom-friendly specification:
# predict hotel occupancy band from tourism scale, China market weight, stay length, and seasonality.
tree_formula <- hotel_occ_level_tertile ~ visitor_arrivals + china_share + avg_stay_monthly_capped + month

tree_model <- rpart::rpart(
  formula = tree_formula,
  data = train_df,
  method = "class",
  parms = list(split = "gini"),
  control = rpart::rpart.control(
    cp = 0.005,
    maxdepth = 4,
    minsplit = 10,
    minbucket = 5,
    xval = 10
  )
)

best_cp <- tree_model$cptable[which.min(tree_model$cptable[, "xerror"]), "CP"]
pruned_tree <- rpart::prune(tree_model, cp = best_cp)

test_pred_class <- predict(pruned_tree, newdata = test_df, type = "class")
test_pred_prob <- predict(pruned_tree, newdata = test_df, type = "prob") |>
  as_tibble()

conf_mat <- caret::confusionMatrix(
  data = test_pred_class,
  reference = test_df$hotel_occ_level_tertile
)

accuracy_tbl <- tibble(
  metric = c("accuracy", "kappa"),
  value = c(conf_mat$overall[["Accuracy"]], conf_mat$overall[["Kappa"]])
)

importance_tbl <- tibble(
  variable = names(pruned_tree$variable.importance),
  importance = as.numeric(pruned_tree$variable.importance)
) |>
  arrange(desc(importance))

predictions_tbl <- test_df |>
  select(date, hotel_occ, hotel_occ_level_tertile) |>
  mutate(
    predicted_class = test_pred_class
  ) |>
  bind_cols(test_pred_prob)

readr::write_csv(predictions_tbl, file.path(output_dir, "decision_tree_test_predictions.csv"))
readr::write_csv(accuracy_tbl, file.path(output_dir, "decision_tree_metrics.csv"))
readr::write_csv(as.data.frame(conf_mat$table), file.path(output_dir, "decision_tree_confusion_matrix.csv"))
readr::write_csv(importance_tbl, file.path(output_dir, "decision_tree_variable_importance.csv"))

png(
  filename = file.path(output_dir, "decision_tree_plot.png"),
  width = 1800,
  height = 1200,
  res = 180
)
rpart.plot::rpart.plot(
  pruned_tree,
  type = 2,
  extra = 104,
  under = TRUE,
  faclen = 0,
  fallen.leaves = TRUE,
  tweak = 1.1,
  main = "Decision Tree for Hotel Occupancy Level"
)
dev.off()

message("Decision tree analysis complete.")
message("Best cp used for pruning: ", round(best_cp, 6))
message("Test accuracy: ", round(conf_mat$overall[['Accuracy']], 4))
print(conf_mat)
print(importance_tbl)
