library(tidyverse)
library(tidymodels)
library(janitor)

.libPaths(c("r-lib", .libPaths()))

set.seed(30100)

dir.create("diagnostics/tuned", showWarnings = FALSE, recursive = TRUE)

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

build_recipe <- function(data, normalize = FALSE) {
  rec <- recipe(fatal ~ ., data = data) |>
    step_indicate_na(n_guns_involved, latitude, longitude) |>
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

basic_recipe <- build_recipe(train_data)
normalized_recipe <- build_recipe(train_data, normalize = TRUE)

prepped_recipe <- prep(basic_recipe)
predictor_count <- ncol(bake(prepped_recipe, new_data = NULL)) - 1

roc_auc_fatal <- metric_tweak("roc_auc_fatal", roc_auc, event_level = "second")
metric_fn <- metric_set(roc_auc_fatal, accuracy, bal_accuracy)
control <- control_grid(save_workflow = TRUE)

score_predictions <- function(pred_df, threshold = 0.5) {
  pred_class <- factor(
    if_else(pred_df$.pred_fatal >= threshold, "fatal", "non_fatal"),
    levels = c("non_fatal", "fatal")
  )

  outcome <- as.integer(pred_df$fatal == "fatal")
  cm <- table(truth = pred_df$fatal, predicted = pred_class)

  tibble(
    threshold = threshold,
    roc_auc = roc_auc_vec(pred_df$fatal, pred_df$.pred_fatal, event_level = "second"),
    accuracy = accuracy_vec(pred_df$fatal, pred_class),
    bal_accuracy = bal_accuracy_vec(pred_df$fatal, pred_class),
    sensitivity = sens_vec(pred_df$fatal, pred_class, event_level = "second"),
    specificity = spec_vec(pred_df$fatal, pred_class, event_level = "second"),
    brier = mean((outcome - pred_df$.pred_fatal) ^ 2),
    tn = unname(cm["non_fatal", "non_fatal"]),
    fp = unname(cm["non_fatal", "fatal"]),
    fn = unname(cm["fatal", "non_fatal"]),
    tp = unname(cm["fatal", "fatal"])
  )
}

calc_ece <- function(pred_df, bins = 10) {
  pred_df |>
    mutate(outcome = as.integer(fatal == "fatal")) |>
    mutate(bin = ntile(.pred_fatal, bins)) |>
    group_by(bin) |>
    summarise(
      mean_pred = mean(.pred_fatal),
      obs_rate = mean(outcome),
      n = n(),
      .groups = "drop"
    ) |>
    summarise(ece = weighted.mean(abs(obs_rate - mean_pred), w = n)) |>
    pull(ece)
}

collect_preds <- function(fit_obj, data) {
  data |>
    select(fatal) |>
    bind_cols(
      predict(fit_obj, data, type = "prob"),
      predict(fit_obj, data, type = "class")
    )
}

choose_threshold <- function(fit_obj, valid_data) {
  pred <- collect_preds(fit_obj, valid_data)

  map_dfr(seq(0.05, 0.95, by = 0.01), function(threshold) {
    score_predictions(pred, threshold) |>
      select(threshold, bal_accuracy, sensitivity, specificity)
  }) |>
    arrange(desc(bal_accuracy), abs(threshold - 0.5)) |>
    slice(1)
}

summarize_probabilities <- function(pred_df, label) {
  pred_df |>
    group_by(fatal) |>
    summarise(
      mean_prob = mean(.pred_fatal),
      median_prob = median(.pred_fatal),
      p90 = quantile(.pred_fatal, 0.9),
      p95 = quantile(.pred_fatal, 0.95),
      share_ge_05 = mean(.pred_fatal >= 0.5),
      .groups = "drop"
    ) |>
    mutate(model = label, .before = 1)
}

logit_spec <- logistic_reg() |>
  set_engine("glm") |>
  set_mode("classification")

rf_original_spec <- rand_forest(mtry = 25, min_n = 5, trees = 400) |>
  set_engine("ranger", probability = TRUE) |>
  set_mode("classification")

xgb_original_spec <- boost_tree(
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

folds <- vfold_cv(train_data, v = 3, strata = fatal)

rf_tune_spec <- rand_forest(
  mtry = tune(),
  min_n = tune(),
  trees = tune()
) |>
  set_engine("ranger", probability = TRUE, importance = "permutation") |>
  set_mode("classification")

rf_workflow <- workflow() |>
  add_recipe(basic_recipe) |>
  add_model(rf_tune_spec)

rf_params <- extract_parameter_set_dials(rf_workflow) |>
  update(
    mtry = mtry(c(5L, min(180L, predictor_count))),
    min_n = min_n(c(2L, 40L)),
    trees = trees(c(400L, 1600L))
  )

set.seed(30100)
rf_grid <- grid_space_filling(rf_params, size = 10)

set.seed(30100)
rf_tuned <- tune_grid(
  rf_workflow,
  resamples = folds,
  grid = rf_grid,
  metrics = metric_fn,
  control = control
)

best_rf <- select_best(rf_tuned, metric = "roc_auc_fatal")
rf_tuned_spec <- finalize_model(rf_tune_spec, best_rf)
rf_tuned_workflow <- workflow() |>
  add_recipe(basic_recipe) |>
  add_model(rf_tuned_spec)

xgb_tune_spec <- boost_tree(
  trees = tune(),
  tree_depth = tune(),
  learn_rate = tune(),
  mtry = tune(),
  min_n = tune(),
  loss_reduction = tune(),
  sample_size = tune(),
  stop_iter = tune()
) |>
  set_engine("xgboost", eval_metric = "auc") |>
  set_mode("classification")

xgb_workflow <- workflow() |>
  add_recipe(basic_recipe) |>
  add_model(xgb_tune_spec)

xgb_params <- extract_parameter_set_dials(xgb_workflow) |>
  update(
    trees = trees(c(300L, 900L)),
    tree_depth = tree_depth(c(2L, 10L)),
    learn_rate = learn_rate(c(-3.2, -0.4)),
    mtry = mtry(c(5L, min(220L, predictor_count))),
    min_n = min_n(c(2L, 40L)),
    loss_reduction = loss_reduction(c(-4, 1.5)),
    sample_size = sample_prop(c(0.5, 1.0)),
    stop_iter = stop_iter(c(15L, 60L))
  )

set.seed(30100)
xgb_grid <- grid_space_filling(xgb_params, size = 8)

set.seed(30100)
xgb_tuned <- tune_grid(
  xgb_workflow,
  resamples = folds,
  grid = xgb_grid,
  metrics = metric_fn,
  control = control
)

best_xgb <- select_best(xgb_tuned, metric = "roc_auc_fatal")
xgb_tuned_spec <- finalize_model(xgb_tune_spec, best_xgb)
xgb_tuned_workflow <- workflow() |>
  add_recipe(basic_recipe) |>
  add_model(xgb_tuned_spec)

logit_fit <- workflow() |>
  add_recipe(normalized_recipe) |>
  add_model(logit_spec) |>
  fit(train_data)

rf_original_fit <- workflow() |>
  add_recipe(basic_recipe) |>
  add_model(rf_original_spec) |>
  fit(train_data)

xgb_original_fit <- workflow() |>
  add_recipe(basic_recipe) |>
  add_model(xgb_original_spec) |>
  fit(train_data)

rf_tuned_fit <- fit(rf_tuned_workflow, train_data)
xgb_tuned_fit <- fit(xgb_tuned_workflow, train_data)

test_preds <- list(
  "Logistic regression" = collect_preds(logit_fit, test_data),
  "Random forest | original" = collect_preds(rf_original_fit, test_data),
  "Random forest | tuned" = collect_preds(rf_tuned_fit, test_data),
  "XGBoost | original" = collect_preds(xgb_original_fit, test_data),
  "XGBoost | tuned" = collect_preds(xgb_tuned_fit, test_data)
)

test_results_default <- imap_dfr(test_preds, function(pred_df, label) {
  score_predictions(pred_df, threshold = 0.5) |>
    mutate(model = label, ece = calc_ece(pred_df), .before = 1)
})

probability_summary <- imap_dfr(test_preds, summarize_probabilities)

val_split <- initial_split(train_data, prop = 0.80, strata = fatal)
subtrain <- training(val_split)
valid <- testing(val_split)

logit_fit_val <- workflow() |>
  add_recipe(build_recipe(subtrain, normalize = TRUE)) |>
  add_model(logit_spec) |>
  fit(subtrain)

rf_original_fit_val <- workflow() |>
  add_recipe(build_recipe(subtrain)) |>
  add_model(rf_original_spec) |>
  fit(subtrain)

xgb_original_fit_val <- workflow() |>
  add_recipe(build_recipe(subtrain)) |>
  add_model(xgb_original_spec) |>
  fit(subtrain)

rf_tuned_fit_val <- workflow() |>
  add_recipe(build_recipe(subtrain)) |>
  add_model(rf_tuned_spec) |>
  fit(subtrain)

xgb_tuned_fit_val <- workflow() |>
  add_recipe(build_recipe(subtrain)) |>
  add_model(xgb_tuned_spec) |>
  fit(subtrain)

threshold_tbl <- bind_rows(
  choose_threshold(logit_fit_val, valid) |> mutate(model = "Logistic regression"),
  choose_threshold(rf_original_fit_val, valid) |> mutate(model = "Random forest | original"),
  choose_threshold(rf_tuned_fit_val, valid) |> mutate(model = "Random forest | tuned"),
  choose_threshold(xgb_original_fit_val, valid) |> mutate(model = "XGBoost | original"),
  choose_threshold(xgb_tuned_fit_val, valid) |> mutate(model = "XGBoost | tuned")
) |>
  relocate(model)

test_results_threshold <- threshold_tbl |>
  mutate(
    results = map2(model, threshold, function(model_label, threshold_value) {
      score_predictions(test_preds[[model_label]], threshold_value) |>
        mutate(model = model_label, ece = calc_ece(test_preds[[model_label]]), .before = 1)
    })
  ) |>
  select(results) |>
  unnest(results)

rf_resample_summary <- collect_metrics(rf_tuned) |>
  filter(.metric == "roc_auc_fatal") |>
  arrange(desc(mean))

xgb_resample_summary <- collect_metrics(xgb_tuned) |>
  filter(.metric == "roc_auc_fatal") |>
  arrange(desc(mean))

param_summary <- bind_rows(
  best_rf |> mutate(model = "Random forest"),
  best_xgb |> mutate(model = "XGBoost")
) |>
  relocate(model)

comparison_tbl <- test_results_default |>
  select(model, roc_auc, accuracy, bal_accuracy, sensitivity, specificity, brier, ece) |>
  mutate(across(where(is.numeric), ~ round(.x, 4)))

threshold_comparison_tbl <- test_results_threshold |>
  select(model, threshold, roc_auc, accuracy, bal_accuracy, sensitivity, specificity, brier, ece) |>
  mutate(across(where(is.numeric), ~ round(.x, 4)))

readr::write_csv(param_summary, "diagnostics/tuned/best_params.csv")
readr::write_csv(comparison_tbl, "diagnostics/tuned/test_results_default.csv")
readr::write_csv(threshold_comparison_tbl, "diagnostics/tuned/test_results_threshold.csv")
readr::write_csv(probability_summary, "diagnostics/tuned/probability_summary.csv")
readr::write_csv(rf_resample_summary, "diagnostics/tuned/rf_resample_summary.csv")
readr::write_csv(xgb_resample_summary, "diagnostics/tuned/xgb_resample_summary.csv")
readr::write_csv(collect_metrics(rf_tuned), "diagnostics/tuned/rf_all_metrics.csv")
readr::write_csv(collect_metrics(xgb_tuned), "diagnostics/tuned/xgb_all_metrics.csv")

cat("Predictor count after recipe:", predictor_count, "\n\n")
cat("Best RF parameters:\n")
print(best_rf)
cat("\nBest XGBoost parameters:\n")
print(best_xgb)
cat("\nDefault-threshold test results:\n")
print(comparison_tbl)
cat("\nThreshold-moved test results:\n")
print(threshold_comparison_tbl)
