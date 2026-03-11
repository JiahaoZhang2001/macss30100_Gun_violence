library(tidyverse)
library(tidymodels)
library(janitor)

set.seed(30100)

data_path <- "Data/stage3.csv"
if (!file.exists(data_path)) {
  stop("Expected data file not found at Data/stage3.csv")
}

stage3 <- readr::read_csv(data_path, show_col_types = FALSE) |>
  clean_names() |>
  mutate(
    date = as.Date(date),
    year = as.integer(format(date, "%Y")),
    month = as.integer(format(date, "%m")),
    day_of_week = factor(weekdays(date)),
    weekend = factor(if_else(lubridate::wday(date, week_start = 1) >= 6, "weekend", "weekday")),
    fatal = factor(if_else(n_killed > 0, "fatal", "non_fatal"), levels = c("non_fatal", "fatal"))
  )

analysis_df <- stage3 |>
  transmute(
    fatal,
    year = factor(year),
    month = factor(month),
    day_of_week,
    weekend,
    state = factor(state),
    city_or_county = factor(city_or_county),
    gun_stolen = factor(gun_stolen),
    gun_type = factor(gun_type),
    n_guns_involved,
    latitude,
    longitude,
    congressional_district = factor(congressional_district),
    state_house_district = factor(state_house_district),
    state_senate_district = factor(state_senate_district),
    addr_has_block = factor(if_else(str_detect(replace_na(address, ""), regex("block", ignore_case = TRUE)), "yes", "no")),
    addr_has_intersection = factor(if_else(str_detect(replace_na(address, ""), regex(" and | & | at ", ignore_case = TRUE)), "yes", "no")),
    addr_has_road = factor(if_else(str_detect(replace_na(address, ""), regex("road|\\brd\\b|street|\\bst\\b|avenue|\\bave\\b|boulevard|\\bblvd\\b", ignore_case = TRUE)), "yes", "no")),
    has_teen = factor(if_else(str_detect(replace_na(participant_age_group, ""), stringr::fixed("Teen 12-17")), "yes", "no")),
    has_child = factor(if_else(str_detect(replace_na(participant_age_group, ""), stringr::fixed("Child 0-11")), "yes", "no"))
  )

split_obj <- initial_split(analysis_df, prop = 0.80, strata = fatal)
train_data <- training(split_obj)
test_data <- testing(split_obj)

model_n <- min(20000, nrow(analysis_df))
train_n <- floor(model_n * 0.80)
test_n <- model_n - train_n

if (nrow(train_data) > train_n) {
  train_data <- train_data |>
    group_by(fatal) |>
    slice_sample(prop = train_n / nrow(train_data)) |>
    ungroup()
}

if (nrow(test_data) > test_n) {
  test_data <- test_data |>
    group_by(fatal) |>
    slice_sample(prop = test_n / nrow(test_data)) |>
    ungroup()
}

counts <- train_data |>
  count(fatal)
class_ratio <- counts$n[counts$fatal == "non_fatal"] / counts$n[counts$fatal == "fatal"]

train_up <- bind_rows(
  filter(train_data, fatal == "non_fatal"),
  filter(train_data, fatal == "fatal") |>
    slice_sample(n = counts$n[counts$fatal == "non_fatal"], replace = TRUE)
) |>
  slice_sample(prop = 1)

build_recipe <- function(data, normalize = FALSE) {
  rec <- recipe(fatal ~ ., data = data) |>
    step_indicate_na(
      n_guns_involved,
      latitude,
      longitude
    ) |>
    step_impute_median(all_numeric_predictors()) |>
    step_unknown(all_nominal_predictors()) |>
    step_other(city_or_county, gun_stolen, gun_type, threshold = 0.01, other = "other") |>
    step_novel(all_nominal_predictors()) |>
    step_dummy(all_nominal_predictors()) |>
    step_zv(all_predictors())

  if (normalize) {
    rec <- rec |>
      step_normalize(all_numeric_predictors())
  }

  rec
}

rf_spec <- rand_forest(mtry = 25, min_n = 5, trees = 400) |>
  set_engine("ranger", probability = TRUE) |>
  set_mode("classification")

rf_weighted_spec <- rand_forest(mtry = 25, min_n = 5, trees = 400) |>
  set_engine("ranger", probability = TRUE, class.weights = c(non_fatal = 1, fatal = class_ratio)) |>
  set_mode("classification")

xgb_spec <- boost_tree(
  trees = 363,
  tree_depth = 2,
  learn_rate = 0.0187,
  mtry = 8,
  min_n = 13,
  loss_reduction = 2.31,
  sample_size = 0.727
) |>
  set_engine("xgboost", eval_metric = "auc") |>
  set_mode("classification")

xgb_weighted_spec <- boost_tree(
  trees = 363,
  tree_depth = 2,
  learn_rate = 0.0187,
  mtry = 8,
  min_n = 13,
  loss_reduction = 2.31,
  sample_size = 0.727
) |>
  set_engine("xgboost", eval_metric = "auc", scale_pos_weight = class_ratio) |>
  set_mode("classification")

logit_spec <- logistic_reg() |>
  set_engine("glm") |>
  set_mode("classification")

svm_spec <- svm_rbf(cost = 10, rbf_sigma = 0.01) |>
  set_engine("kernlab") |>
  set_mode("classification")

choose_threshold <- function(fit_obj, val_data) {
  pred <- val_data |>
    bind_cols(predict(fit_obj, val_data, type = "prob"))

  map_dfr(seq(0.05, 0.95, by = 0.01), function(threshold) {
    pred_class <- factor(
      if_else(pred$.pred_fatal >= threshold, "fatal", "non_fatal"),
      levels = c("non_fatal", "fatal")
    )

    tibble(
      threshold = threshold,
      bal_accuracy = bal_accuracy_vec(pred$fatal, pred_class),
      sensitivity = sens_vec(pred$fatal, pred_class, event_level = "second"),
      specificity = spec_vec(pred$fatal, pred_class, event_level = "second")
    )
  }) |>
    arrange(desc(bal_accuracy), abs(threshold - 0.5)) |>
    slice(1)
}

score_model <- function(name, fit_obj, threshold = 0.5) {
  pred <- test_data |>
    bind_cols(predict(fit_obj, test_data, type = "prob"))

  pred_class <- factor(
    if_else(pred$.pred_fatal >= threshold, "fatal", "non_fatal"),
    levels = c("non_fatal", "fatal")
  )

  cm <- conf_mat(
    tibble(fatal = pred$fatal, .pred_class = pred_class),
    truth = fatal,
    estimate = .pred_class
  )

  tibble(
    setup = name,
    threshold = threshold,
    roc_auc = roc_auc_vec(pred$fatal, pred$.pred_fatal, event_level = "second"),
    accuracy = accuracy_vec(pred$fatal, pred_class),
    bal_accuracy = bal_accuracy_vec(pred$fatal, pred_class),
    sensitivity_fatal = sens_vec(pred$fatal, pred_class, event_level = "second"),
    specificity_nonfatal = spec_vec(pred$fatal, pred_class, event_level = "second"),
    tn = cm$table[1, 1],
    fp = cm$table[1, 2],
    fn = cm$table[2, 1],
    tp = cm$table[2, 2]
  )
}

val_split <- initial_split(train_data, prop = 0.80, strata = fatal)
subtrain <- training(val_split)
valid <- testing(val_split)

rf_fit <- workflow() |>
  add_recipe(build_recipe(train_data)) |>
  add_model(rf_spec) |>
  fit(train_data)

rf_fit_weighted <- workflow() |>
  add_recipe(build_recipe(train_data)) |>
  add_model(rf_weighted_spec) |>
  fit(train_data)

rf_fit_oversampled <- workflow() |>
  add_recipe(build_recipe(train_up)) |>
  add_model(rf_spec) |>
  fit(train_up)

rf_fit_val <- workflow() |>
  add_recipe(build_recipe(subtrain)) |>
  add_model(rf_spec) |>
  fit(subtrain)

rf_best_th <- choose_threshold(rf_fit_val, valid)

xgb_fit <- workflow() |>
  add_recipe(build_recipe(train_data)) |>
  add_model(xgb_spec) |>
  fit(train_data)

xgb_fit_weighted <- workflow() |>
  add_recipe(build_recipe(train_data)) |>
  add_model(xgb_weighted_spec) |>
  fit(train_data)

xgb_fit_oversampled <- workflow() |>
  add_recipe(build_recipe(train_up)) |>
  add_model(xgb_spec) |>
  fit(train_up)

xgb_fit_val <- workflow() |>
  add_recipe(build_recipe(subtrain)) |>
  add_model(xgb_spec) |>
  fit(subtrain)

xgb_best_th <- choose_threshold(xgb_fit_val, valid)

logit_fit <- workflow() |>
  add_recipe(build_recipe(train_data, normalize = TRUE)) |>
  add_model(logit_spec) |>
  fit(train_data)

logit_fit_oversampled <- workflow() |>
  add_recipe(build_recipe(train_up, normalize = TRUE)) |>
  add_model(logit_spec) |>
  fit(train_up)

logit_fit_val <- workflow() |>
  add_recipe(build_recipe(subtrain, normalize = TRUE)) |>
  add_model(logit_spec) |>
  fit(subtrain)

logit_best_th <- choose_threshold(logit_fit_val, valid)

svm_fit <- workflow() |>
  add_recipe(build_recipe(train_data, normalize = TRUE)) |>
  add_model(svm_spec) |>
  fit(train_data)

svm_fit_oversampled <- workflow() |>
  add_recipe(build_recipe(train_up, normalize = TRUE)) |>
  add_model(svm_spec) |>
  fit(train_up)

svm_fit_val <- workflow() |>
  add_recipe(build_recipe(subtrain, normalize = TRUE)) |>
  add_model(svm_spec) |>
  fit(subtrain)

svm_best_th <- choose_threshold(svm_fit_val, valid)

threshold_tbl <- bind_rows(
  mutate(rf_best_th, model = "Random forest"),
  mutate(xgb_best_th, model = "XGBoost"),
  mutate(logit_best_th, model = "Logistic regression"),
  mutate(svm_best_th, model = "SVM (RBF)")
) |>
  select(model, threshold, bal_accuracy, sensitivity, specificity)

results_tbl <- bind_rows(
  score_model("Random forest | default", rf_fit, 0.5),
  score_model("Random forest | class weight", rf_fit_weighted, 0.5),
  score_model("Random forest | oversampled", rf_fit_oversampled, 0.5),
  score_model("Random forest | threshold moved", rf_fit, rf_best_th$threshold[[1]]),
  score_model("XGBoost | default", xgb_fit, 0.5),
  score_model("XGBoost | class weight", xgb_fit_weighted, 0.5),
  score_model("XGBoost | oversampled", xgb_fit_oversampled, 0.5),
  score_model("XGBoost | threshold moved", xgb_fit, xgb_best_th$threshold[[1]]),
  score_model("Logistic regression | default", logit_fit, 0.5),
  score_model("Logistic regression | oversampled", logit_fit_oversampled, 0.5),
  score_model("Logistic regression | threshold moved", logit_fit, logit_best_th$threshold[[1]]),
  score_model("SVM (RBF) | default", svm_fit, 0.5),
  score_model("SVM (RBF) | oversampled", svm_fit_oversampled, 0.5),
  score_model("SVM (RBF) | threshold moved", svm_fit, svm_best_th$threshold[[1]])
) |>
  mutate(across(where(is.numeric), ~ round(.x, 4)))

default_tbl <- results_tbl |>
  filter(str_detect(setup, "\\| default$")) |>
  transmute(
    model = str_remove(setup, " \\| default$"),
    roc_auc,
    accuracy,
    bal_accuracy,
    sensitivity_fatal,
    specificity_nonfatal
  )

cat("Training class ratio non_fatal:fatal =", round(class_ratio, 4), "\n\n")
cat("Best thresholds from validation split:\n")
print(threshold_tbl)
cat("\nHeld-out comparison across imbalance strategies:\n")
print(results_tbl)

readr::write_csv(threshold_tbl, "threshold_results_balanced_accuracy.csv")
readr::write_csv(results_tbl, "model_results_imbalance_strategies.csv")
readr::write_csv(default_tbl, "three_model_default_results.csv")
