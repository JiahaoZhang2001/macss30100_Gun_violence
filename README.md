# MACS 30100 Final Project

This repository contains my final project for MACS 30100 on predicting fatal vs. non-fatal gun violence incidents from structured incident-level features.

## Main files

- [`Final Episode/final_submission_episode.pdf`](Final%20Episode/final_submission_episode.pdf): final written report
- [`Final Episode/final_submission_episode.qmd`](Final%20Episode/final_submission_episode.qmd): source file for the report
- [`Final Episode/final_model_pipeline.R`](Final%20Episode/final_model_pipeline.R): main modeling pipeline for the final comparison and imbalance analysis
- [`Final Episode/tune_tree_models.R`](Final%20Episode/tune_tree_models.R): tuning workflow for the tree-based models

## Supplementary files

- [`Final Episode/images/interactive_incident_map.html`](Final%20Episode/images/interactive_incident_map.html): interactive leaflet map supplement
- [`Final Episode/images/interactive_incident_map_preview.png`](Final%20Episode/images/interactive_incident_map_preview.png): static preview of the interactive map used in the PDF

## Notes

- The analysis code is written primarily with `tidyverse` and `tidymodels`.
- The report is the main submission document; the HTML map is only a supplement and should be opened in a web browser.
