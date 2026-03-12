if (!require("pacman")) install.packages("pacman")

pacman::p_load(
  tidyverse,
  readxl,
  lubridate,
  writexl,
  here
)

# Run this script from the repository root or open the repo in RStudio.
raw_path <- here::here("data", "raw", "Name your insight (2).xlsx")
processed_dir <- here::here("data", "processed")
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

col_names <- c(
  "date",
  "avg_stay_monthly",
  "hotel_occ",
  "spend_per_capita",
  "tourism_receipts",
  "avg_stay_annual",
  "visitor_arrivals",
  "visitor_arrivals_china"
)

# Skip the first 29 metadata rows so the import starts at the actual observation block.
raw_tbl <- readxl::read_excel(
  path = raw_path,
  sheet = "My Series",
  skip = 29,
  col_names = FALSE
) |>
  setNames(col_names) |>
  mutate(
    date = as.Date(date),
    across(-date, as.numeric)
  ) |>
  arrange(date)

# Keep rows that contain the full monthly core needed by all four analysis modules.
monthly_clean <- raw_tbl |>
  filter(
    !is.na(date),
    !is.na(avg_stay_monthly),
    !is.na(hotel_occ),
    !is.na(visitor_arrivals),
    !is.na(visitor_arrivals_china)
  ) |>
  mutate(
    year = year(date),
    month = month(date),
    quarter = quarter(date),
    period = case_when(
      date <= as.Date("2020-01-01") ~ "pre_covid",
      date <= as.Date("2021-12-01") ~ "covid_shock",
      TRUE ~ "recovery"
    ),
    china_share = visitor_arrivals_china / visitor_arrivals,
    china_share_pct = china_share * 100
  )

# Cap the upper tail of length of stay so extreme pandemic months do not dominate clustering or trees.
stay_cap <- quantile(monthly_clean$avg_stay_monthly, probs = 0.95, na.rm = TRUE)

monthly_clean <- monthly_clean |>
  mutate(
    avg_stay_monthly_capped = pmin(avg_stay_monthly, stay_cap),
    visitor_arrivals_millions = visitor_arrivals / 1e6,
    visitor_arrivals_china_thousands = visitor_arrivals_china / 1e3
  )

occ_cuts <- quantile(monthly_clean$hotel_occ, probs = c(1 / 3, 2 / 3), na.rm = TRUE)

analysis_ready <- monthly_clean |>
  mutate(
    cluster_z_visitor_arrivals = as.numeric(scale(visitor_arrivals)),
    cluster_z_china_share = as.numeric(scale(china_share)),
    cluster_z_hotel_occ = as.numeric(scale(hotel_occ)),
    cluster_z_avg_stay_monthly_capped = as.numeric(scale(avg_stay_monthly_capped)),
    hotel_occ_level_tertile = case_when(
      hotel_occ <= occ_cuts[[1]] ~ "low",
      hotel_occ <= occ_cuts[[2]] ~ "medium",
      TRUE ~ "high"
    ),
    hotel_occ_level_business = case_when(
      hotel_occ < 70 ~ "low",
      hotel_occ <= 85 ~ "medium",
      TRUE ~ "high"
    )
  ) |>
  mutate(
    hotel_occ_level_tertile = factor(hotel_occ_level_tertile, levels = c("low", "medium", "high")),
    hotel_occ_level_business = factor(hotel_occ_level_business, levels = c("low", "medium", "high"))
  ) |>
  mutate(
    dataset_split = if_else(row_number() <= floor(n() * 0.8), "train", "test")
  )

readr::write_csv(monthly_clean, file.path(processed_dir, "tourism_monthly_clean.csv"))
readr::write_csv(analysis_ready, file.path(processed_dir, "tourism_four_part_analysis_ready.csv"))

writexl::write_xlsx(
  list(
    monthly_clean = monthly_clean,
    analysis_ready_all = analysis_ready
  ),
  path = file.path(processed_dir, "tourism_four_part_analysis_ready.xlsx")
)

message("Data preparation complete.")
message("Rows in final analysis-ready data: ", nrow(analysis_ready))
message("Date range: ", min(analysis_ready$date), " to ", max(analysis_ready$date))
message("Avg stay cap (95th percentile): ", round(stay_cap, 6))
message("Hotel occupancy cut points: ", round(occ_cuts[[1]], 6), " / ", round(occ_cuts[[2]], 6))
