# Predicting Fatal vs. Non-Fatal Gun Violence Incidents from Structured Incident-Level Features

---

# Project Description

## Summary

This repository contains my final project for MACS 30100. The project studies whether structured incident-level records can help distinguish fatal gun violence incidents from non-fatal ones.

- **Topic**: binary prediction of fatal versus non-fatal gun violence incidents
- **Research question**: can a cleaned set of structured incident features provide useful signal for screening higher-risk cases?
- **Why it matters**: in this setting, the practical goal is not perfect classification. It is whether incident records can support earlier screening of potentially more severe cases while staying realistic about class imbalance and false positives.

## Additional info

**Total lines of code**: approximately 1,288 executable lines across the three main submission files: `final_submission_episode.qmd`, `final_model_pipeline.R`, and `tune_tree_models.R`.

**Methods and Analysis**: The analysis is written in R with `tidyverse` and `tidymodels`. I build a leakage-safe preprocessing and modeling pipeline, compare logistic regression, random forest, and XGBoost, and then evaluate class-imbalance strategies including class weighting, oversampling, and threshold moving.

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
└── Final Episode/
    ├── final_submission_episode.qmd
    ├── final_submission_episode.pdf
    ├── final_model_pipeline.R
    ├── tune_tree_models.R
    ├── bibliography.bib
    ├── three_model_default_results.csv
    ├── model_results_imbalance_strategies.csv
    ├── threshold_results_balanced_accuracy.csv
    ├── threshold_results_specificity_constrained.csv
    ├── images/
    │   ├── interactive_incident_map.html
    │   ├── interactive_incident_map_preview.png
    │   ├── probability_distributions.png
    │   ├── rf_shap_summary.png
    │   └── tuning_summary.png
    └── diagnostics/
        └── plots/
            ├── calibration.png
            └── confusion_matrices.png
```

- `Final Episode/` contains the final report, main analysis scripts, saved model results, and supporting figures.
- `Final Episode/images/` stores figures and supplementary visual materials referenced in the final submission.
- `Final Episode/diagnostics/` stores additional checking outputs that support the modeling workflow.

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
- **Interactive map supplement**: [`Final Episode/images/interactive_incident_map.html`](Final%20Episode/images/interactive_incident_map.html)
- **Slides**: to be added later
- **Presentation video**: not added yet
