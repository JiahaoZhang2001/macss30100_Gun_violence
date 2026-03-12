# Predicting Fatal vs. Non-Fatal Gun Violence Incidents from Structured Incident-Level Features

---

# Project Description

## Summary

This repository contains my final project for MACS 30100. The project studies whether structured incident-level records can help distinguish fatal gun violence incidents from non-fatal ones.

- **Topic**: binary prediction of fatal versus non-fatal gun violence incidents
- **Research question**: can structured incident-level information be used to distinguish fatal gun violence incidents from non-fatal incidents, and does it provide useful signal for screening higher-risk cases?
- **Why it matters**: in this setting, the practical goal is not perfect classification. It is whether incident records can support earlier screening of potentially more severe cases while staying realistic about class imbalance and false positives.

## Additional info

**Methods and Analysis**: The analysis is written in R with `tidyverse` and `tidymodels`. I build a leakage-safe preprocessing and modeling pipeline, compare logistic regression, random forest, and XGBoost, and then evaluate class-imbalance strategies including class weighting, oversampling, and threshold moving.

**Main findings**: The main result is that this task is better understood as a screening problem than as a strong classification problem. Structured incident-level features do contain some useful signal for distinguishing fatal from non-fatal incidents, but the signal is limited and much of it appears to come from broader context, especially location and timing, rather than from rich incident-specific detail. In the three-model comparison, random forest had the strongest overall ranking performance by ROC AUC, while logistic regression stayed reasonably competitive and easier to interpret. But with the default `0.50` cutoff, all three models did a poor job catching fatal cases, so class imbalance turned out to be one of the main practical problems in the project. Among the imbalance strategies, class weighting helped the least, oversampling was the most aggressive for recall, and threshold moving gave the clearest trade-off between catching more fatal cases and creating more false positives.

**Conclusion**: Overall, the project suggests that structured incident-level features cannot support a strong or broadly deployable classifier here, but they do provide limited screening signal for separating fatal from non-fatal incidents. Under that framing, the most defensible final choice for this dataset and use case was the specificity-constrained threshold-moving random forest, which improved fatal-case detection relative to the default threshold while keeping non-fatal specificity near the intended bound.

**Project strength**: model pipeline design and evaluation under class imbalance.

---

# Data

- **Gun violence incident data (cleaned course project working file)**  
  Link: [jamesqo/gun-violence-data](https://github.com/jamesqo/gun-violence-data)  
  Collection method: download from the public GitHub repository, followed by local cleaning and restructuring earlier in the course workflow. This final report starts from a cleaned local working dataset, `stage3.csv`, derived from that source.  
  Notes: the final report uses `stage3.csv` as the auditable analysis file rather than rebuilding the dataset during rendering. The file is not committed to GitHub because it exceeds the single-file size limit.

---

# Repository Structure

```text
macss30100_Gun_violence/
├── README.md
├── .gitignore
├── docs/
│   ├── .nojekyll
│   ├── index.html
│   └── interactive_incident_map.html
└── Final Episode/
    ├── final_submission_episode.qmd
    ├── final_submission_episode.pdf
    ├── final_model_pipeline.R
    ├── tune_tree_models.R
    ├── bibliography.bib
    ├── results/
    │   ├── three_model_default_results.csv
    │   ├── model_results_imbalance_strategies.csv
    │   ├── threshold_results_balanced_accuracy.csv
    │   └── threshold_results_specificity_constrained.csv
    ├── images/
    │   ├── interactive_incident_map.html
    │   ├── interactive_incident_map_preview.png
    │   ├── probability_distributions.png
    │   ├── rf_shap_summary.png
    │   └── tuning_summary.png
```

- `Final Episode/` contains the final report, main analysis scripts, saved model results, and supporting figures.
- `docs/` stores the GitHub Pages files for the interactive map supplement.
- `Final Episode/results/` stores the saved result tables used in the report.
- `Final Episode/images/` stores figures and supplementary visual materials referenced in the final submission.

Saved result tables:

- `results/three_model_default_results.csv` stores the default-threshold baseline comparison for logistic regression, random forest, and XGBoost.
- `results/model_results_imbalance_strategies.csv` stores the held-out results for the class-weighting, oversampling, and threshold-moving setups.
- `results/threshold_results_balanced_accuracy.csv` stores the threshold-search results when balanced accuracy alone is used as the validation criterion.
- `results/threshold_results_specificity_constrained.csv` stores the threshold-search results under the more conservative validation-stage specificity constraint used in the final recommended operating point.

---

# Libraries

| Library | Version |
|--------|--------|
| tidyverse | 2.0.0 |
| tidymodels | 1.4.1 |
| themis | 1.0.3 |
| janitor | 2.2.1 |
| patchwork | 1.3.2 |
| scales | 1.4.0 |
| broom | 1.0.11 |
| glue | 1.8.0 |
| leaflet | 2.2.3 |
| htmlwidgets | 1.6.4 |
| vip | 0.4.5 |
| xgboost | 3.2.0.1 |

---

# Contributions

- **Jiahao Zhang**: completed the project individually, including data preparation decisions, feature engineering, tidymodels workflows, model tuning, class-imbalance analysis, threshold evaluation, diagnostics, visualizations, and final report writing.

For the main submitted scripts:

- `Final Episode/final_submission_episode.qmd`  
  Purpose: final Quarto report that loads the cleaned dataset and saved results, rebuilds key plots and tables, and presents the final analysis.

- `Final Episode/final_model_pipeline.R`  
  Purpose: main modeling pipeline for fitting the final comparison models and class-imbalance setups with `tidymodels`.

- `Final Episode/tune_tree_models.R`  
  Purpose: tuning workflow for the tree-based models used in the final comparison.

---

# AI Usage Statement

I used AI tools as support tools during the project, mainly for:

- checking wording and consistency in the written report
- debugging small coding issues in R and Quarto
- learning how to use some packages and functions more effectively
- understanding what a fuller model deployment workflow would look like
- renaming files and organizing the final submission repository

AI was mainly a support tool in the project rather than a replacement for my own decisions. When I used suggestions from AI, I tried to understand them before applying them and then adapted them to my own work. I remain responsible for the accuracy of the report, code, and repository contents.

---

# Project Links

- **Final written report**: [`Final Episode/final_submission_episode.pdf`](Final%20Episode/final_submission_episode.pdf)
- **Quarto source**: [`Final Episode/final_submission_episode.qmd`](Final%20Episode/final_submission_episode.qmd)
- **Interactive map webpage**: [Open the interactive map](https://jiahaozhang2001.github.io/macss30100_Gun_violence/)
- **Slides**: to be added later
- **Presentation video**: not added yet
