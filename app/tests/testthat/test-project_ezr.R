# --- Tests of the EZR parts and the start files (README "Tests") ---

# --- Wait until a condition holds, up to some seconds (a test helper) (README "Tests") ---
ezr_wait <- function(condition, seconds) {
  for (i in seq_len(seconds * 2)) {
    if (isTRUE(condition())) return(TRUE)
    Sys.sleep(0.5)
  }
  isTRUE(condition())
}

# --- Only folders with usable names, by last use (README "How it works") ---
test_that("ezr_projects() lists folders with usable names directly under projects/, by last use", {
  root <- withr::local_tempdir()
  expect_identical(nrow(ezr_projects(root)), 0L)
  for (name in c("studyA", "studyB", "研究C", ".hidden")) {
    dir.create(file.path(root, "projects", name, "outputs"), recursive = TRUE)
  }
  file.create(file.path(root, "projects", c(".gitkeep", "memo.txt")))
  dir.create(file.path(root, "projects", "studyA", "inner"))
  Sys.setFileTime(file.path(root, "projects", "studyA", "outputs"), Sys.time() - 3600)
  Sys.setFileTime(file.path(root, "projects", "studyB", "outputs"), Sys.time())
  expect_identical(ezr_projects(root)$name, c("studyB", "studyA"))
  unlink(file.path(root, "projects", "studyB"), recursive = TRUE)
  expect_identical(ezr_projects(root)$name, "studyA")
})

# --- Projects without outputs/ are ordered by the folder's time (README "How it works") ---
test_that("ezr_projects() orders projects without outputs/ by the folder's time", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "projects", "old", "outputs"), recursive = TRUE)
  dir.create(file.path(root, "projects", "fresh"))
  Sys.setFileTime(file.path(root, "projects", "old", "outputs"), Sys.time() - 3600)
  Sys.setFileTime(file.path(root, "projects", "fresh"), Sys.time())
  expect_identical(ezr_projects(root)$name, c("fresh", "old"))
})

# --- Creates data/ and outputs/, and recreates them if deleted (README "Projects and records") ---
test_that("ezr_project_dir() creates data/ and outputs/, and recreates them if deleted", {
  root <- withr::local_tempdir()
  project_dir <- ezr_project_dir("studyA", root)
  expect_identical(project_dir, file.path(root, "projects", "studyA"))
  expect_true(all(dir.exists(file.path(project_dir, c("data", "outputs")))))
  unlink(file.path(project_dir, c("data", "outputs")), recursive = TRUE)
  ezr_project_dir("studyA", root)
  expect_true(all(dir.exists(file.path(project_dir, c("data", "outputs")))))
})

# --- Record folder: time + 4 digits, next number if taken (README "Projects and records") ---
test_that("ezr_run_dir() returns <YYYYMMDDHHMM>_<4 digits> and moves the number on if taken", {
  outputs <- withr::local_tempdir()
  now <- as.POSIXct("2026-11-05 12:34:56", tz = "UTC")
  first <- ezr_run_dir(outputs, now)
  expect_identical(dirname(first), outputs)
  expect_match(basename(first), "^202611051234_[0-9]{4}$")
  expect_identical(ezr_run_dir(outputs, now), first)
  dir.create(first)
  number <- as.integer(sub(".*_", "", basename(first)))
  expect_identical(basename(ezr_run_dir(outputs, now)),
                   sprintf("202611051234_%04d", (number + 1L) %% 10000L))
})

# --- Files not CSV/Excel or over 15 MB come back with a reason (README "Projects and records") ---
test_that("ezr_check_data() returns files not CSV or Excel or larger than 15 MB, with the reason", {
  files <- data.frame(
    name = c("検査.csv", "血圧.XLSX", "古い.xls", "メモ.txt", "ちょうど.csv", "大きい.csv", "名前だけ"),
    size = c(10, 10, 10, 10, 15 * 1024^2, 15 * 1024^2 + 1, 10)
  )
  expect_identical(ezr_check_data(files), c(
    "メモ.txt (not CSV or Excel)",
    "大きい.csv (larger than 15 MB)",
    "名前だけ (not CSV or Excel)"
  ))
  expect_identical(ezr_check_data(files[c(1:3, 5), ]), character())
})

# --- Data is copied into data/; same-name files stay (README "Projects and records") ---
test_that("ezr_add_data() copies to data/ and does not delete files with the same name", {
  src <- withr::local_tempdir()
  data_dir <- file.path(withr::local_tempdir(), "data")
  put <- function(name, text) {
    path <- tempfile(tmpdir = src)
    writeLines(text, path)
    data.frame(name = name, size = file.size(path), datapath = path)
  }
  expect_identical(ezr_add_data(rbind(put("検査.csv", "番号,年齢"), put("血圧.xlsx", "表")), data_dir),
                   c("Added 検査.csv", "Added 血圧.xlsx"))
  expect_identical(readLines(file.path(data_dir, "検査.csv")), "番号,年齢")
  expect_identical(ezr_add_data(put("検査.csv", "番号,体重"), data_dir),
                   "検査.csv already exists, so it was added as 検査_2.csv")
  expect_identical(readLines(file.path(data_dir, "検査.csv")), "番号,年齢")
  expect_identical(readLines(file.path(data_dir, "検査_2.csv")), "番号,体重")
  again <- rbind(put("検査.csv", "番号,年齢"), put("検査.csv", "番号,体重"))
  expect_identical(ezr_add_data(again, data_dir), c(
    "検査.csv with the same content already exists, so it was not added",
    "検査_2.csv with the same content already exists, so it was not added"
  ))
  expect_identical(ezr_add_data(put("検査.csv", "番号,身長"), data_dir),
                   "検査.csv already exists, so it was added as 検査_3.csv")
  binary <- tempfile(tmpdir = src)
  writeBin(as.raw(0:255), binary)
  ezr_add_data(data.frame(name = "表.xls", size = 256, datapath = binary), data_dir)
  expect_identical(unname(tools::md5sum(file.path(data_dir, "表.xls"))),
                   unname(tools::md5sum(binary)))
  expect_setequal(list.files(data_dir), c("検査.csv", "検査_2.csv", "検査_3.csv", "血圧.xlsx", "表.xls"))
})

# --- Picks up data/ files and the files the R script read (README "Projects and records") ---
test_that("ezr_describe(), ezr_data_files(), ezr_read_files() pick up data/ files and files read", {
  project_dir <- file.path(withr::local_tempdir(), "projects", "studyA")
  dir.create(file.path(project_dir, "data", "sub"), recursive = TRUE)
  writeLines("番号,年齢", file.path(project_dir, "data", "検査.csv"))
  writeLines("表", file.path(project_dir, "data", "sub", "血圧.xlsx"))
  info <- ezr_describe(ezr_data_files(project_dir), project_dir)
  paths <- vapply(info, function(x) x$path, "")
  expect_setequal(paths, c("data/検査.csv", "data/sub/血圧.xlsx"))
  csv <- info[[which(paths == "data/検査.csv")]]
  expect_identical(csv$sha256, unname(tools::sha256sum(file.path(project_dir, "data", "検査.csv"))))
  expect_identical(csv$bytes, file.size(file.path(project_dir, "data", "検査.csv")))
  script <- tempfile(fileext = ".R")
  writeLines(c(
    sprintf("Dataset <- read.table(\"%s/data/検査.csv\", header=TRUE)", project_dir),
    "ketsuatsu <- readXL(\"data/sub/血圧.xlsx\", sheet=\"Sheet1\")",
    "other <- read.csv(\"/elsewhere/other.csv\")",
    sprintf("gone <- read.csv(\"%s/data/無い.csv\")", project_dir)
  ), script)
  expect_setequal(ezr_read_files(script, project_dir),
                  file.path(project_dir, "data", c("検査.csv", "sub/血圧.xlsx")))
  expect_identical(ezr_read_files(tempfile(fileext = ".R"), project_dir), character())
  unquoted <- tempfile(fileext = ".R")
  writeLines(c("x <- 1:3", "summary(x)"), unquoted)
  expect_identical(ezr_read_files(unquoted, project_dir), character())
  empty <- tempfile(fileext = ".R")
  file.create(empty)
  expect_identical(ezr_read_files(empty, project_dir), character())
})

# --- The environment keeps the renv.lock SHA-256 and Zip origin (README "Projects and records") ---
test_that("ezr_environment() keeps R and EZR versions, the renv.lock SHA-256 and the Zip origin", {
  skip_if(!nzchar(system.file(package = "RcmdrPlugin.EZR")), "EZR is not installed")
  root <- withr::local_tempdir()
  without <- ezr_environment(root)
  expect_identical(without$r_version, R.version.string)
  expect_identical(without$ezr, as.character(utils::packageVersion("RcmdrPlugin.EZR")))
  expect_null(without$renv_lock_sha256)
  expect_null(without$template_version)
  lock <- file.path(root, "renv.lock")
  writeLines("{}", lock)
  writeLines(c("# The version this folder was made from", "template ezr_dist_r461_en abc",
               "created 2026-11-14"), file.path(root, "TEMPLATE_VERSION.txt"))
  with <- ezr_environment(root)
  expect_identical(with$renv_lock_sha256, digest::digest(lock, algo = "sha256", file = TRUE))
  expect_identical(with$template_version, c("template ezr_dist_r461_en abc", "created 2026-11-14"))
})

# --- The notice tells where to open what was asked for (README "How it works") ---
test_that("ezr_browser_text() tells where to open what it was asked to open", {
  root <- normalizePath(withr::local_tempdir())
  dir.create(file.path(root, "projects", "studyA"), recursive = TRUE)
  report <- file.path(root, "projects", "studyA", "report.html")
  writeLines("<html></html>", report)
  web <- "https://www.jichi.ac.jp/saitama-sct/SaitamaHP.files/statmed.html"
  expect_match(ezr_browser_text(web, root), web, fixed = TRUE)
  expect_match(ezr_browser_text(report, root), "RStudio's Files pane", fixed = TRUE)
  expect_match(ezr_browser_text(paste0("file://", report), root), "projects/studyA/report.html",
               fixed = TRUE)
  four <- paste("file:///", report, sep = "")
  expect_match(ezr_browser_text(four, root), "projects/studyA/report.html", fixed = TRUE)
  help_page <- "http://127.0.0.1:12345/library/Rcmdr/html/Commander.html"
  expect_match(ezr_browser_text(help_page, root), "RStudio's Help pane", fixed = TRUE)
  manual <- file.path(withr::local_tempdir(), "guide.pdf")
  file.create(manual)
  expect_match(ezr_browser_text(paste0("file:///", manual), root), "This file (guide.pdf)",
               fixed = TRUE)
})

# --- Sends ezr_start.R only without the marker, then leaves it (README "How it works") ---
test_that("ezr_autostart() sends ezr_start.R to the console only without the marker", {
  root <- withr::local_tempdir()
  flag <- file.path(root, "flag")
  sent <- character()
  local_mocked_bindings(sendToConsole = function(code, ...) sent <<- c(sent, code),
                        .package = "rstudioapi")
  expect_false(ezr_autostart(root, flag))
  expect_false(file.exists(flag))
  writeLines("", file.path(root, "ezr_start.R"))
  expect_true(ezr_autostart(root, flag))
  expect_true(file.exists(flag))
  expect_identical(sent, sprintf("source(%s)", deparse(file.path(root, "ezr_start.R"))))
  expect_false(ezr_autostart(root, flag))
  expect_length(sent, 1L)
})

# --- The marks against translation are added only once (README "How it works") ---
test_that("ezr_no_translate() adds the marks against translation only once", {
  meta <- "<meta name=\"google\" content=\"notranslate\">"
  page <- c("<!DOCTYPE html>", "<html lang=\"en\" class=\"noVNC_loading\">", "<head>",
            "<title>noVNC</title>", "</head>", "<body></body>", "</html>")
  marked <- ezr_no_translate(page)
  expect_identical(marked[2], "<html translate=\"no\" lang=\"en\" class=\"noVNC_loading\">")
  expect_identical(marked[3:4], c("<head>", meta))
  expect_length(marked, length(page) + 1L)
  expect_identical(ezr_no_translate(marked), marked)
  expect_identical(ezr_no_translate("<p>EZR</p>"), c(meta, "<p>EZR</p>"))
})

# --- The EZR tab's page has the marks and the text input box (README "How it works") ---
test_that("ezr_web() puts the marks against translation and the text input box in the EZR tab", {
  skip_if_not(file.exists("/usr/share/novnc/vnc.html"), "no noVNC (outside the container)")
  web <- file.path(withr::local_tempdir(), "web")
  ezr_web(web)
  page <- readLines(file.path(web, "ezr.html"), warn = FALSE)
  expect_length(grep("<html translate=\"no\"", page, fixed = TRUE), 1L)
  expect_length(grep("<meta name=\"google\" content=\"notranslate\">", page, fixed = TRUE), 1L)
  expect_true(any(grepl("id='ezr_ime_text'", page, fixed = TRUE)))
  entry <- paste(readLines(file.path(web, "index.html"), warn = FALSE), collapse = "\n")
  expect_match(entry, "<html translate=\"no\">", fixed = TRUE)
  expect_match(entry, "content=\"notranslate\"", fixed = TRUE)
})

# --- ezr_start.R holds one expression that calls ezr_start() (README "How it works") ---
test_that("ezr_start.R holds only one expression, which calls ezr_start()", {
  exprs <- parse(file.path("..", "..", "ezr_start.R"), keep.source = FALSE)
  expect_length(exprs, 1L)
  expect_match(paste(deparse(exprs[[1]]), collapse = "\n"), "ezr$ezr_start(root)", fixed = TRUE)
})

# --- The "Open EZR" window checks data, report and name first (README "How it works") ---
test_that("ezr_start_server() does not open when a check fails, and returns the choice and data", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "projects", "studyA"), recursive = TRUE)
  upload <- file.path(withr::local_tempdir(), "0")
  writeLines("id,age", upload)
  good <- data.frame(name = "exam.csv", size = file.size(upload), datapath = upload)
  bad <- data.frame(name = "memo.txt", size = 10, datapath = upload)
  env <- environment(ezr_start_server)
  real <- get("ezr_reports_running", envir = env)
  withr::defer(assign("ezr_reports_running", real, envir = env))
  busy <- FALSE
  assign("ezr_reports_running", function(...) busy, envir = env)
  calls <- list()
  server <- ezr_start_server(root, stop_app = function(x) calls <<- c(calls, list(x)))
  lost <- list(list(lost = TRUE))
  shiny::testServer(server, {
    session$setInputs(pick = ".new", name = "studyB", data = bad)
    expect_match(output$data_problem, "Some files cannot be added", fixed = TRUE)
    session$setInputs(done = 1)
  })
  expect_identical(calls, lost)
  calls <- list()
  busy <- TRUE
  shiny::testServer(server, {
    session$setInputs(pick = "studyA")
    session$setInputs(done = 1)
    expect_match(output$problem, "The report of the previous session", fixed = TRUE)
  })
  busy <- FALSE
  expect_identical(calls, lost)
  calls <- list()
  shiny::testServer(server, {
    session$setInputs(pick = ".new", name = "study B")
    session$setInputs(done = 1)
    expect_match(output$problem, "Start the name with a letter or digit", fixed = TRUE)
    session$setInputs(name = "studyA")
    expect_identical(output$problem, "")
    session$setInputs(done = 1)
    expect_match(output$problem, "\"studyA\" already exists", fixed = TRUE)
  })
  expect_identical(calls, lost)
  calls <- list()
  shiny::testServer(server, {
    session$setInputs(pick = ".new", name = " studyB ", data = good)
    expect_identical(output$data_problem, "")
    session$setInputs(done = 1)
  })
  expect_identical(calls, list(list(project = "studyB", notes = "Added exam.csv")))
  expect_identical(readLines(file.path(root, "projects", "studyB", "data", "exam.csv")), "id,age")
  calls <- list()
  shiny::testServer(server, {
    session$setInputs(pick = "studyA")
    session$setInputs(done = 1)
  })
  expect_identical(calls, list(list(project = "studyA", notes = character())))
  calls <- list()
  shiny::testServer(server, session$setInputs(cancel = 1))
  expect_identical(calls, list(NULL))
})

# --- markdown.Rmd becomes markdown.html with figures (README "Projects and records") ---
test_that("ezr_render_report() turns markdown.Rmd into markdown.html with figures", {
  skip_if_not(rmarkdown::pandoc_available(), "pandoc is not available")
  skip_if(!nzchar(system.file(package = "RcmdrPlugin.EZR")), "EZR is not installed")
  project_dir <- file.path(withr::local_tempdir(), "projects", "studyA")
  run_dir <- file.path(project_dir, "outputs", "202610171200_0001")
  dir.create(run_dir, recursive = TRUE)
  writeLines(c(
    "---", "title: \"Trial\"", "---", "",
    "```{r}", "Dataset <- data.frame(年齢 = c(30, 45, 60))",
    "res <- numSummary2(Dataset[,\"年齢\"], statistics = \"mean\")", "res", "```", "",
    "```{r}", "stop(\"intentional error\")", "```", "",
    "```{r}", "x11(width = 7, height = 7); par(lwd = 1, las = 1)",
    "hist(Dataset$年齢, main = \"年齢\")", "```"
  ), file.path(run_dir, "markdown.Rmd"))
  for (name in c("console.log", "script.R", "output.txt")) {
    writeLines("test", file.path(run_dir, name))
  }
  ezr_write_meta(run_dir, list(status = "closed"))
  command <- sprintf("source(%s); ezr_render_report(%s, %s)",
                     deparse(normalizePath(file.path("..", "..", "R", "project_ezr.R"))),
                     deparse(run_dir), deparse(project_dir))
  system2("Rscript", c("-e", shQuote(command)), stdout = FALSE, stderr = FALSE)
  html <- readLines(file.path(run_dir, "markdown.html"), warn = FALSE)
  expect_true(any(grepl("intentional error", html, fixed = TRUE)))
  expect_true(any(grepl("data:image/png;base64", html, fixed = TRUE)))
  expect_false(file.exists(file.path(run_dir, "markdown.log")))
  expect_false(dir.exists(file.path(run_dir, "markdown_files")))
  meta <- jsonlite::read_json(file.path(run_dir, "meta.json"))
  expect_true(nzchar(meta$records_finalized_at))
  expect_length(unlist(meta$rng_at_report_start$kind), 3L)
  expect_length(unlist(meta$rng_at_report_end$kind), 3L)
  paths <- vapply(meta$records, function(x) x$path, "")
  expect_setequal(paths,
                  c("console.log", "script.R", "markdown.Rmd", "output.txt", "markdown.html"))
  for (record in meta$records) {
    expect_identical(record$sha256,
                     digest::digest(file.path(run_dir, record$path), algo = "sha256", file = TRUE))
  }

})

# --- A report is made even without the YAML header (README "Projects and records") ---
test_that("ezr_render_report() makes markdown.html even without a YAML header in markdown.Rmd", {
  skip_if_not(rmarkdown::pandoc_available(), "pandoc is not available")
  skip_if(!nzchar(system.file(package = "RcmdrPlugin.EZR")), "EZR is not installed")
  project_dir <- file.path(withr::local_tempdir(), "projects", "studyA")
  run_dir <- file.path(project_dir, "outputs", "202611141200_0001")
  dir.create(run_dir, recursive = TRUE)
  writeLines(c("```{r}", "1 + 1", "```"), file.path(run_dir, "markdown.Rmd"))
  command <- sprintf("source(%s); ezr_render_report(%s, %s)",
                     deparse(normalizePath(file.path("..", "..", "R", "project_ezr.R"))),
                     deparse(run_dir), deparse(project_dir))
  system2("Rscript", c("-e", shQuote(command)), stdout = FALSE, stderr = FALSE)
  expect_true(file.exists(file.path(run_dir, "markdown.html")))
  expect_false(file.exists(file.path(run_dir, "markdown.log")))
})

# --- Opens EZR, keeps records, and ends when closed (README "Projects and records") ---
test_that("ezr_open() opens EZR, keeps records in the record folder, and ends when closed", {
  skip_if(!nzchar(Sys.which("Xvnc")), "no virtual display (outside the container)")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc is not available")
  fifo_path <- "/tmp/ezr-stdin"
  skip_if(ezr_r_alive(fifo_path), "EZR is running in this container (skipped to keep it open)")

  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  file.copy(file.path("..", "..", "R", "project_ezr.R"), file.path(root, "R"))
  withr::local_options(browser = function(url) invisible(url))
  withr::local_dir(root)

  current_file <- "/tmp/ezr-current"
  writeLines(c("check", "-"), current_file)
  real_send <- ezr_send
  current_at_send <- character()
  assign("ezr_send", function(fifo_path, lines) {
    if (length(lines) > 1L) current_at_send <<- readLines(current_file)
    real_send(fifo_path, lines)
  }, envir = environment(ezr_open))
  withr::defer(assign("ezr_send", real_send, envir = environment(ezr_open)))

  run_dir <- suppressMessages(ezr_open("check"))
  expect_identical(current_at_send, c("", run_dir))
  expect_identical(readLines(current_file), c("check", run_dir))
  assign("ezr_send", real_send, envir = environment(ezr_open))
  project_dir <- file.path(normalizePath(root), "projects", "check")
  expect_match(run_dir, paste0("^", project_dir, "/outputs/[0-9]{12}_[0-9]{4}$"))
  expect_true(dir.exists(file.path(project_dir, "data")))

  files <- file.path(run_dir, c("console.log", "script.R", "markdown.Rmd", "output.txt"))
  expect_true(ezr_wait(function() all(file.exists(files)), 300))
  console <- function() readLines(files[1], warn = FALSE)
  expect_true(any(grepl("Rcmdr Version", console(), fixed = TRUE)))

  ezr_send(fifo_path, "cat(\"EZR_WD:\", getwd(), \"\\n\")")
  expect_true(ezr_wait(function() any(grepl("^EZR_WD:", console())), 60))
  expect_identical(gsub("^EZR_WD: | $", "", grep("^EZR_WD:", console(), value = TRUE)[1]),
                   project_dir)

  meta_path <- file.path(run_dir, "meta.json")
  expect_true(ezr_wait(function() file.exists(meta_path), 60))
  opened <- jsonlite::read_json(meta_path)
  expect_identical(c(opened$project, opened$status), c("check", "open"))
  expect_true(nzchar(opened$environment$ezr))
  expect_length(opened$data_at_open, 0L)
  expect_length(unlist(opened$rng_at_open$kind), 3L)

  plot_file <- function(n) file.path(run_dir, "plots", sprintf("plot_%03d.png", n))
  ezr_send(fifo_path, c("x11(width = 7, height = 7); par(lwd = 1, las = 1)",
                        "plot(1:10, main = \"Plot 1\")"))
  expect_true(ezr_wait(function() file.exists(plot_file(1)), 30))
  first <- tools::md5sum(plot_file(1))
  ezr_send(fifo_path, "abline(h = 5, col = \"red\")")
  expect_true(ezr_wait(function() !identical(tools::md5sum(plot_file(1)), first), 30))
  ezr_send(fifo_path, c("par(mfrow = c(1, 2))", "plot(10:1)", "plot(1:3)"))
  expect_true(ezr_wait(function() file.exists(plot_file(2)), 30))
  Sys.sleep(5)
  expect_false(file.exists(plot_file(3)))
  ezr_send(fifo_path, c("par(mfrow = c(1, 1))", "print(lattice::xyplot(1:3 ~ 1:3))"))
  expect_true(ezr_wait(function() file.exists(plot_file(3)), 30))
  head <- readBin(plot_file(1), "raw", 4096)
  expect_length(grepRaw(charToRaw("tRNS"), head), 0L)
  expect_true(head[26] %in% as.raw(c(0, 2, 3)))

  csv <- c("年齢,性別", "40,男", "50,女", "60,男")
  writeLines(csv, file.path(project_dir, "data", "utf8.csv"))
  writeLines(iconv(csv, "UTF-8", "CP932"), file.path(project_dir, "data", "cp932.csv"),
             useBytes = TRUE)
  ezr_send(fifo_path, c(
    "d1 <- read.csv(\"data/utf8.csv\")",
    "d2 <- read.csv(\"data/cp932.csv\", fileEncoding = \"CP932\")",
    "boxplot(年齢 ~ 性別, data = d1, main = \"年齢の分布\"); invisible(dev.off())",
    "cat(\"EZR_JA:\", names(d1), names(d2), nrow(d2), grDevices::X11.options()$type, \"\\n\")"
  ))
  expect_true(ezr_wait(function() any(grepl("^EZR_JA:", console())), 60))
  expect_identical(grep("^EZR_JA:", console(), value = TRUE)[1], "EZR_JA: 年齢 性別 年齢 性別 3 cairo ")
  expect_gt(length(system2("fc-list", ":lang=ja", stdout = TRUE)), 0)

  csv_path <- deparse(file.path(project_dir, "data", "utf8.csv"))
  commands <- c(sprintf("Dataset <- read.csv(%s)", csv_path), "hist(Dataset$年齢, main = \"年齢\")")
  ezr_send(fifo_path, sprintf("Rcmdr::doItAndPrint(%s)", vapply(commands, deparse, "")))
  script <- function() readLines(file.path(run_dir, "script.R"), warn = FALSE)
  expect_true(ezr_wait(function() any(grepl("hist(Dataset", script(), fixed = TRUE)), 60))

  expect_true("session.screen0.workspaces: 1" %in% readLines(path.expand("~/.fluxbox/init")))
  keys <- readLines(path.expand("~/.fluxbox/keys"))
  expect_false(any(grepl(":(Exit|Restart|RootMenu|Close|Kill)", keys)))

  report <- file.path(run_dir, "markdown.html")
  ezr_send(fifo_path, paste("tcltk::tcl(\"after\", 0, function() {",
                            "Rcmdr::closeCommander(ask = FALSE); Rcmdr::Commander() })"))
  Sys.sleep(8)
  expect_true(ezr_r_alive(fifo_path))
  ezr_send(fifo_path, c("Rcmdr::doItAndPrint(\"after_restart <- 1\")",
                        "cat(\"EZR_BROWSER:\", is.function(getOption(\"browser\")), \"\\n\")"))
  expect_true(ezr_wait(function() any(grepl("after_restart", script(), fixed = TRUE)), 60))
  expect_true(any(grepl("hist(Dataset", script(), fixed = TRUE)))
  expect_true(ezr_wait(function() any(grepl("^EZR_BROWSER: TRUE", console())), 60))
  expect_identical(jsonlite::read_json(meta_path)$status, "open")
  expect_null(jsonlite::read_json(meta_path)$data_at_close)
  expect_identical(sum(readLines(file.path(run_dir, "markdown.Rmd"), warn = FALSE) == "---"), 2L)
  expect_false(file.exists(report))
  ezr_send(fifo_path, "tcltk::tcl(\"after\", 0, function() Rcmdr::Commander())")
  Sys.sleep(8)
  expect_true(ezr_r_alive(fifo_path))
  ezr_send(fifo_path, "Rcmdr::doItAndPrint(\"after_second <- 2\")")
  expect_true(ezr_wait(function() any(grepl("after_second", script(), fixed = TRUE)), 60))
  expect_true(any(grepl("after_restart", script(), fixed = TRUE)))

  ezr_send(fifo_path, c(
    "set.seed(8642)",
    'cat("EZR_RNG_STATE:", paste(.Random.seed, collapse=","), "\\n")'
  ))
  expect_true(ezr_wait(function() any(grepl("^EZR_RNG_STATE:", console())), 30))
  rng_line <- grep("^EZR_RNG_STATE:", console(), value = TRUE)[1]
  expected_rng <- as.integer(strsplit(trimws(sub("^EZR_RNG_STATE:", "", rng_line)), ",")[[1]])
  ezr_send(fifo_path, "Rcmdr::closeCommander(ask = FALSE)")
  expect_true(ezr_wait(function() !ezr_r_alive(fifo_path), 120))
  expect_true(all(file.exists(files)))

  closed <- jsonlite::read_json(meta_path)
  expect_identical(closed$status, "closed")
  data_paths <- vapply(closed$data_at_close, function(x) x$path, "")
  expect_setequal(data_paths, c("data/utf8.csv", "data/cp932.csv"))
  expect_identical(closed$data_at_close[[which(data_paths == "data/utf8.csv")]]$sha256,
                   unname(tools::sha256sum(file.path(project_dir, "data", "utf8.csv"))))
  expect_identical(vapply(closed$read_files, function(x) x$path, ""), "data/utf8.csv")
  expect_true(all(c("script.R", "plots/plot_001.png") %in%
                    vapply(closed$records, function(x) x$path, "")))

  expect_true(ezr_wait(function() file.exists(report), 180))
  expect_true(ezr_wait(function() {
    meta <- tryCatch(jsonlite::read_json(meta_path), error = function(e) NULL)
    !is.null(meta$records_finalized_at)
  }, 60))
  final <- jsonlite::fromJSON(meta_path)
  expect_identical(final$rng_at_close$state, expected_rng)
  expect_identical(jsonlite::read_json(meta_path)$rng_at_open, opened$rng_at_open)
  expect_true(all(c("console.log", "markdown.html") %in% final$records$path))
  expect_false("meta.json" %in% final$records$path)
  for (record in jsonlite::read_json(meta_path)$records) {
    expect_identical(record$sha256,
                     digest::digest(file.path(run_dir, record$path), algo = "sha256", file = TRUE))
  }

  expect_true(any(grepl("data:image/png;base64", readLines(report, warn = FALSE), fixed = TRUE)))
  expect_false(file.exists(file.path(run_dir, "markdown.log")))

  problems <- grep("エラー|Error|警告|Warning", console(), value = TRUE)
  expect_identical(grep("BadMatch", problems, value = TRUE, invert = TRUE), character(0))
})

# --- Stops without switching when the previous EZR does not close (README "How it works") ---
test_that("ezr_open() stops without switching when the previous EZR does not close", {
  skip_if(!nzchar(Sys.which("Xvnc")), "no virtual display (outside the container)")
  fifo_path <- "/tmp/ezr-stdin"
  skip_if(ezr_r_alive(fifo_path), "EZR is running in this container (skipped to keep it open)")

  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  file.copy(file.path("..", "..", "R", "project_ezr.R"), file.path(root, "R"))
  withr::local_options(browser = function(url) invisible(url))
  withr::local_dir(root)

  run_a <- suppressMessages(ezr_open("busy"))
  expect_true(ezr_wait(function() file.exists(file.path(run_a, "meta.json")), 300))
  ezr_send(fifo_path, "Sys.sleep(45)")
  Sys.sleep(1)
  expect_error(suppressMessages(ezr_open("other")), "has not closed yet")
  expect_identical(readLines("/tmp/ezr-current", n = 1L), "busy")
  expect_false(dir.exists(file.path(root, "projects", "other")))
  expect_true(ezr_wait(function() !ezr_r_alive(fifo_path), 120))
  expect_identical(jsonlite::read_json(file.path(run_a, "meta.json"))$status, "closed")
})

# --- Ends an R that stopped early, and opens EZR again (README "How it works") ---
test_that("ezr_open() ends an R that stopped before the commands, and opens EZR again", {
  skip_if(!nzchar(Sys.which("Xvnc")), "no virtual display (outside the container)")
  fifo_path <- "/tmp/ezr-stdin"
  skip_if(ezr_r_alive(fifo_path), "EZR is running in this container (skipped to keep it open)")

  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  file.copy(file.path("..", "..", "R", "project_ezr.R"), file.path(root, "R"))
  withr::local_options(browser = function(url) invisible(url))
  withr::local_dir(root)

  stopped <- file.path(root, "projects", "half", "outputs", "stopped")
  dir.create(stopped, recursive = TRUE)
  writeLines(c("", stopped), "/tmp/ezr-current")
  system(paste("R --interactive --no-save --no-restore --quiet", paste0("0<>", fifo_path),
               ">", shQuote(file.path(stopped, "console.log")), "2>&1"), wait = FALSE)
  expect_true(ezr_wait(function() ezr_r_alive(fifo_path), 30))

  expect_message(run_dir <- ezr_open("half"), "Closing an EZR that stopped partway", fixed = TRUE)
  expect_false(identical(run_dir, stopped))
  expect_identical(readLines("/tmp/ezr-current"), c("half", run_dir))
  expect_true(ezr_wait(function() file.exists(file.path(run_dir, "meta.json")), 300))
  ezr_send(fifo_path, "Rcmdr::closeCommander(ask = FALSE)")
  expect_true(ezr_wait(function() !ezr_r_alive(fifo_path), 120))
})


# --- Opens the next EZR only after the previous report is made (README "How it works") ---
test_that("ezr_open() opens the next EZR only after the report of the previous session is made", {
  skip_if(!nzchar(Sys.which("Xvnc")), "no virtual display (outside the container)")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc is not available")
  fifo_path <- "/tmp/ezr-stdin"
  skip_if(ezr_r_alive(fifo_path), "EZR is running in this container (skipped to keep it open)")
  expect_true(ezr_wait(function() !ezr_reports_running(), 300))

  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  file.copy(file.path("..", "..", "R", "project_ezr.R"), file.path(root, "R"))
  withr::local_options(browser = function(url) invisible(url))
  withr::local_dir(root)

  run_a <- suppressMessages(ezr_open("slow"))
  console <- file.path(run_a, "console.log")
  expect_true(ezr_wait(function() file.exists(file.path(run_a, "meta.json")), 300))
  ezr_send(fifo_path, c("Rcmdr::doItAndPrint(\"Sys.sleep(10)\")", "cat(\"EZR_SLEPT\\n\")"))
  expect_true(ezr_wait(function() any(grepl("^EZR_SLEPT", readLines(console, warn = FALSE))), 120))
  rmd <- function() readLines(file.path(run_a, "markdown.Rmd"), warn = FALSE)
  expect_true(ezr_wait(function() any(grepl("Sys.sleep(10)", rmd(), fixed = TRUE)), 60))

  expect_message(run_b <- ezr_open("next"), "The report of the previous session is being made",
                 fixed = TRUE)
  expect_true(file.exists(file.path(run_a, "markdown.html")))
  expect_false(is.null(jsonlite::read_json(file.path(run_a, "meta.json"))$records_finalized_at))
  expect_false(ezr_reports_running())
  expect_true(ezr_wait(function() file.exists(file.path(run_b, "meta.json")), 300))
  ezr_send(fifo_path, "Rcmdr::closeCommander(ask = FALSE)")
  expect_true(ezr_wait(function() !ezr_r_alive(fifo_path), 120))
  expect_true(ezr_wait(function() !ezr_reports_running(), 300))
})

# --- The project already open shows the running EZR, not a new one (README "How it works") ---
test_that("ezr_open() shows the running EZR, without reopening, when it is the same project", {
  fifo_path <- "/tmp/ezr-stdin"
  current_file <- "/tmp/ezr-current"
  skip_if(ezr_r_alive(fifo_path), "EZR is running in this container (skipped to keep it open)")
  root <- withr::local_tempdir()
  env <- environment(ezr_open)
  real <- mget(c("ezr_display", "ezr_r_alive", "ezr_send"), envir = env)
  withr::defer(list2env(real, envir = env))
  sent <- list()
  assign("ezr_display", function() invisible(NULL), envir = env)
  assign("ezr_r_alive", function(fifo_path) TRUE, envir = env)
  assign("ezr_send", function(fifo_path, lines) sent <<- c(sent, list(lines)), envir = env)
  before <- if (file.exists(current_file)) readLines(current_file, warn = FALSE)
  withr::defer(if (is.null(before)) unlink(current_file) else writeLines(before, current_file))
  writeLines(c("studyA", file.path(root, "projects", "studyA", "outputs", "run")), current_file)
  opened <- character()
  withr::local_options(browser = function(url) opened <<- c(opened, url))
  expect_null(ezr_open("studyA", root))
  expect_identical(opened, "http://localhost:6080/")
  expect_length(sent, 0L)
  expect_false(dir.exists(file.path(root, "projects", "studyA")))
  expect_identical(readLines(current_file, n = 1L), "studyA")
})

# --- Copying the RNG state changes nothing, seeded or not (README "Projects and records") ---
test_that("RNG snapshots preserve initialized and uninitialized states", {
  withr::local_seed(1234)
  expected <- runif(5)
  set.seed(1234)
  before <- .Random.seed
  snapshot <- ezr_rng_snapshot()
  expect_identical(snapshot$state, before)
  expect_identical(snapshot$kind, RNGkind())
  expect_identical(.Random.seed, before)
  expect_identical(runif(5), expected)
  expect_identical(snapshot$state, before)
  run <- withr::local_tempdir()
  ezr_write_meta(run, list(rng = snapshot))
  restored <- jsonlite::fromJSON(file.path(run, "meta.json"))$rng
  expect_identical(restored$state, snapshot$state)
  rm(".Random.seed", envir = .GlobalEnv)
  snapshot <- ezr_rng_snapshot()
  expect_null(snapshot$state)
  expect_false(exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
})

# --- A running process is not taken as ended; a missing one is (README "How it works") ---
test_that("a live console writer cannot have its hashes finalized", {
  skip_if_not(dir.exists("/proc/self"), "Linux process information required")
  expect_false(ezr_wait_for_exit(Sys.getpid(), timeout = 0))
  expect_true(ezr_wait_for_exit(.Machine$integer.max, timeout = 0))
})

# --- A failed report: markdown.log is hashed after its writer (README "Projects and records") ---
test_that("a failed report is hashed as markdown.log after its writer finishes", {
  skip_if_not(rmarkdown::pandoc_available(), "pandoc required")
  skip_if(!nzchar(system.file(package = "RcmdrPlugin.EZR")), "EZR required")
  project <- withr::local_tempdir()
  run <- file.path(project, "outputs", "failed-report")
  dir.create(run, recursive = TRUE)
  for (name in c("console.log", "script.R", "output.txt")) {
    writeLines("test", file.path(run, name))
  }
  writeLines(c("---", "output: nonexistent_ezr_output_format", "---", "test"),
              file.path(run, "markdown.Rmd"))
  ezr_write_meta(run, list(status = "closed"))
  command <- sprintf("source(%s); ezr_render_report(%s, %s)",
                     deparse(normalizePath(file.path("..", "..", "R", "project_ezr.R"))),
                     deparse(run), deparse(project))
  system2("Rscript", c("-e", shQuote(command)), stdout = FALSE, stderr = FALSE)
  expect_true(file.exists(file.path(run, "markdown.log")))
  expect_false(file.exists(file.path(run, "markdown.html")))
  meta <- jsonlite::read_json(file.path(run, "meta.json"))
  expect_true(nzchar(meta$records_finalized_at))
  records <- meta$records
  paths <- vapply(records, function(x) x$path, "")
  expect_true("markdown.log" %in% paths)
  expect_identical(records[[which(paths == "markdown.log")]]$sha256,
                   digest::digest(file.path(run, "markdown.log"), algo = "sha256", file = TRUE))
})

# --- While the EZR R runs, the report is made but not hashed (README "Projects and records") ---
test_that("the report is made but its hashes are not finalized while the EZR R still runs", {
  skip_if_not(dir.exists("/proc/self"), "Linux process information required")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc required")
  skip_if(!nzchar(system.file(package = "RcmdrPlugin.EZR")), "EZR required")
  project <- withr::local_tempdir()
  run <- file.path(project, "outputs", "live-writer")
  dir.create(run, recursive = TRUE)
  for (name in c("console.log", "script.R", "output.txt")) {
    writeLines("test", file.path(run, name))
  }
  writeLines(c("---", "title: \"x\"", "---", "", "```{r}", "1 + 1", "```"),
             file.path(run, "markdown.Rmd"))
  ezr_write_meta(run, list(status = "closed", records_finalized_at = "previous-render",
                           records = list(list(path = "console.log", sha256 = "at-closing"))))
  command <- sprintf("source(%s); ezr_render_report(%s, %s",
                     deparse(normalizePath(file.path("..", "..", "R", "project_ezr.R"))),
                     deparse(run), deparse(project))
  live_command <- sprintf("%s, %dL, wait = 0.2)", command, Sys.getpid())
  system2("Rscript", c("-e", shQuote(live_command)), stdout = FALSE, stderr = FALSE)
  expect_true(file.exists(file.path(run, "markdown.html")))
  expect_false(file.exists(file.path(run, "markdown.log")))
  meta <- jsonlite::read_json(file.path(run, "meta.json"))
  expect_null(meta$records_finalized_at)
  expect_true(nzchar(meta$records_not_finalized))
  expect_identical(meta$records[[1]]$sha256, "at-closing")
  expect_length(unlist(meta$rng_at_report_end$kind), 3L)

  system2("Rscript", c("-e", shQuote(paste0(command, ")"))), stdout = FALSE, stderr = FALSE)
  meta <- jsonlite::read_json(file.path(run, "meta.json"))
  expect_true(nzchar(meta$records_finalized_at))
  expect_null(meta$records_not_finalized)
  expect_identical(meta$records[[1]]$sha256,
                   digest::digest(file.path(run, "console.log"), algo = "sha256", file = TRUE))
})

# --- The Windows start file keeps CRLF line endings (README "Code notes") ---
test_that("Windows entry points retain CRLF line endings", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  path <- file.path("..", "..", "..", "start_windows.bat")
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  lf <- which(bytes == as.raw(10))
  expect_true(length(lf) > 0L)
  expect_true(all(lf > 1L))
  expect_true(all(bytes[lf - 1L] == as.raw(13)))
})

# --- Lines that the Windows cmd reads are ASCII only (README "Code notes") ---
test_that("lines cmd reads are ASCII (all of start_windows.bat)", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  start <- file.path("..", "..", "..", "start_windows.bat")
  expect_true(all(readBin(start, "raw", n = file.info(start)$size) < as.raw(128)))
})


# --- The stop waits for records and keeps a failed stop apart (README "How it works") ---
test_that("the stop waits for records, reports STOP_FAILED, and waits after a lost window", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  py <- paste(readLines(file.path("..", "..", "..", "launcher", "standalone.py"), warn = FALSE),
              collapse = "\n")
  stop <- regmatches(py, regexpr("(?s)\\ndef stop_ezr\\(.*?\\n(?=def )", py, perl = TRUE))
  down <- regexpr(" down --timeout", stop, fixed = TRUE)
  expect_lt(regexpr("ezr_records_status()", stop, fixed = TRUE), down)
  expect_lt(regexpr("unfinished_records(", stop, fixed = TRUE), down)
  expect_length(gregexpr('return "WAIT_RECORDS"', stop, fixed = TRUE)[[1]], 2L)
  expect_true(grepl('return "STOP_FAILED"', stop, fixed = TRUE))
  wait <- regmatches(py, regexpr("(?s)\\ndef wait_for_stop_requests\\(.*?\\n(?=def )", py,
                                 perl = TRUE))
  expect_lt(regexpr("for line in sys.stdin", wait, fixed = TRUE),
            regexpr("if stop_ezr(vm, previous) is None", wait, fixed = TRUE))
  expect_false(grepl("force=True", wait, fixed = TRUE))
})

# --- Default project names never clash with files or folders (README "How it works") ---
test_that("default project names avoid existing files and folders without input", {
  root <- withr::local_tempdir()
  now <- as.POSIXct("2026-11-05 12:34:56", tz = "UTC")
  name <- ezr_default_name(root, now)
  expect_true(ezr_valid_name(name))
  dir.create(file.path(root, "projects", name), recursive = TRUE)
  file.create(file.path(root, "projects", paste0(name, "_1")))
  expect_identical(ezr_default_name(root, now), paste0(name, "_2"))
})

# --- Project names: letters, digits, _ . -, alphanumeric first (README "How it works") ---
test_that("ezr_valid_name() passes one name of letters, digits, _ . - that starts alphanumeric", {
  for (name in c("studyA", "A1", "study_1.v2-b")) expect_true(ezr_valid_name(name), info = name)
  for (name in list("", "../studyA", "a/b", ".hidden", "_a", "-a", "研究", "study A", "a\\b",
                    c("a", "b"), NA_character_, 1L, NULL)) {
    expect_false(ezr_valid_name(name), info = paste(name, collapse = ","))
  }
})

# --- "Stop" passes only with closed, final records and a report (README "Projects and records") ---
test_that("GUI stop requires closed, finalized records and an HTML report", {
  never <- function() FALSE
  root <- withr::local_tempdir()
  current <- file.path(root, "current")
  projects <- file.path(root, "projects")
  run <- file.path(projects, "study", "outputs", "run")
  dir.create(run, recursive = TRUE)
  expect_identical(ezr_records_status(current, projects, running = never), 0L)
  writeLines(c("study", run), current)
  expect_identical(ezr_records_status(current, projects, running = never), 2L)
  meta_file <- file.path(run, "meta.json")
  jsonlite::write_json(list(status = "open"), meta_file, auto_unbox = TRUE)
  expect_identical(ezr_records_status(current, projects, running = never), 2L)
  jsonlite::write_json(
    list(status = "closed", records_finalized_at = "time"), meta_file, auto_unbox = TRUE
  )
  expect_identical(ezr_records_status(current, projects, running = function() TRUE), 2L)
  file.create(file.path(run, "markdown.html"))
  expect_identical(ezr_records_status(current, projects, running = never), 0L)
  writeLines(c("study", root), current)
  expect_identical(ezr_records_status(current, projects, running = never), 2L)
})

# --- A short marker or bad meta.json means records not ready (README "Projects and records") ---
test_that("ezr_records_status() blocks the stop with a short marker or an unreadable meta.json", {
  never <- function() FALSE
  root <- withr::local_tempdir()
  current <- file.path(root, "current")
  projects <- file.path(root, "projects")
  run <- file.path(projects, "study", "outputs", "run")
  dir.create(run, recursive = TRUE)
  writeLines("study", current)
  expect_identical(ezr_records_status(current, projects, running = never), 2L)
  writeLines(c("study", run), current)
  writeLines("{", file.path(run, "meta.json"))
  expect_identical(ezr_records_status(current, projects, running = never), 2L)
})

# --- A report that failed (markdown.log) counts as made (README "Projects and records") ---
test_that("a report that could not be made counts as finished (markdown.log)", {
  never <- function() FALSE
  root <- withr::local_tempdir()
  current <- file.path(root, "current")
  projects <- file.path(root, "projects")
  run <- file.path(projects, "study", "outputs", "run")
  dir.create(run, recursive = TRUE)
  writeLines(c("study", run), current)
  jsonlite::write_json(list(status = "closed", records_finalized_at = "time"),
                       file.path(run, "meta.json"), auto_unbox = TRUE)
  writeLines("error", file.path(run, "markdown.log"))
  expect_identical(ezr_records_status(current, projects, running = never), 0L)
})

# --- Open hashes are finalized at stop only once the EZR R ends (README "Projects and records") ---
test_that("unfinalized hashes are finalized before stopping only after the EZR R has ended", {
  never <- function() FALSE
  check <- function(alive) {
    ezr_records_status(current, projects, alive = function() alive, running = never)
  }
  root <- withr::local_tempdir()
  current <- file.path(root, "current")
  projects <- file.path(root, "projects")
  run <- file.path(projects, "study", "outputs", "run")
  dir.create(run, recursive = TRUE)
  writeLines(c("study", run), current)
  writeLines("report", file.path(run, "markdown.html"))
  writeLines("console", file.path(run, "console.log"))
  meta_file <- file.path(run, "meta.json")
  jsonlite::write_json(list(status = "closed", records_not_finalized = "waiting"),
                       meta_file, auto_unbox = TRUE)
  expect_identical(check(TRUE), 2L)
  expect_null(jsonlite::read_json(meta_file)$records_finalized_at)
  expect_identical(check(FALSE), 0L)
  meta <- jsonlite::read_json(meta_file)
  expect_false(is.null(meta$records_finalized_at))
  expect_null(meta$records_not_finalized)
  expect_true(isTRUE(meta$records_finalized_on_stop))
  expect_setequal(vapply(meta$records, function(x) x$path, ""), c("console.log", "markdown.html"))
  expect_identical(check(TRUE), 0L)
})

# --- A report in progress blocks the stop; a lost one does not (README "Projects and records") ---
test_that("a report still being made blocks stopping; one that can no longer come does not", {
  root <- withr::local_tempdir()
  current <- file.path(root, "current")
  projects <- file.path(root, "projects")
  run <- file.path(projects, "study", "outputs", "run")
  dir.create(run, recursive = TRUE)
  writeLines(c("study", run), current)
  writeLines("console", file.path(run, "console.log"))
  meta_file <- file.path(run, "meta.json")
  jsonlite::write_json(list(status = "closed"), meta_file, auto_unbox = TRUE)
  status <- function(alive, running) {
    ezr_records_status(current, projects, alive = function() alive, running = function() running)
  }
  expect_identical(status(FALSE, TRUE), 2L)
  expect_identical(status(TRUE, FALSE), 2L)
  expect_null(jsonlite::read_json(meta_file)$records_finalized_at)
  expect_identical(status(FALSE, FALSE), 0L)
  meta <- jsonlite::read_json(meta_file)
  expect_false(is.null(meta$records_finalized_at))
  expect_true(isTRUE(meta$records_finalized_on_stop))
  expect_true(isTRUE(meta$report_missing_on_stop))
  expect_identical(vapply(meta$records, function(x) x$path, ""), "console.log")
  expect_identical(status(FALSE, FALSE), 0L)
})

# --- A running report R always waits; a gone writer does not (README "Projects and records") ---
test_that("a running report process always waits, and a writer that is gone does not block", {
  root <- withr::local_tempdir()
  current <- file.path(root, "current")
  projects <- file.path(root, "projects")
  run <- file.path(projects, "study", "outputs", "run")
  dir.create(run, recursive = TRUE)
  writeLines(c("study", run), current)
  writeLines("report", file.path(run, "markdown.html"))
  writeLines("console", file.path(run, "console.log"))
  meta_file <- file.path(run, "meta.json")
  status <- function(alive, running) {
    ezr_records_status(current, projects, alive = function() alive, running = function() running)
  }
  jsonlite::write_json(list(status = "closed", records_finalized_at = "time"), meta_file,
                       auto_unbox = TRUE)
  expect_identical(status(FALSE, TRUE), 2L)
  expect_identical(status(FALSE, FALSE), 0L)
  jsonlite::write_json(list(status = "closed", records_not_finalized = "waiting"), meta_file,
                       auto_unbox = TRUE)
  expect_identical(status(FALSE, TRUE), 2L)
  expect_null(jsonlite::read_json(meta_file)$records_finalized_at)
  jsonlite::write_json(list(status = "closed"), meta_file, auto_unbox = TRUE)
  expect_identical(status(FALSE, TRUE), 2L)
  expect_identical(status(TRUE, FALSE), 2L)
  expect_null(jsonlite::read_json(meta_file)$records_finalized_at)
  expect_identical(status(FALSE, FALSE), 0L)
  meta <- jsonlite::read_json(meta_file)
  expect_false(is.null(meta$records_finalized_at))
  expect_true(isTRUE(meta$records_finalized_on_stop))
  expect_null(meta$report_missing_on_stop)
  expect_setequal(vapply(meta$records, function(x) x$path, ""), c("console.log", "markdown.html"))
  expect_identical(status(FALSE, FALSE), 0L)
})

# --- Report Rs are found by command line, not mixed with others (README "How it works") ---
test_that("report processes are found by their command line, not by other processes", {
  proc <- withr::local_tempdir()
  add <- function(name, ...) {
    dir.create(file.path(proc, name))
    parts <- lapply(c(...), function(x) c(charToRaw(x), as.raw(0L)))
    writeBin(unlist(parts), file.path(proc, name, "cmdline"))
  }
  expect_false(ezr_reports_running(proc))
  add("12", "/usr/lib/rstudio-server/bin/rsession", "-u", "rstudio")
  add("self", "R", "-e", "ezr_render_report(1)")
  dir.create(file.path(proc, "13"))
  expect_false(ezr_reports_running(proc))
  add("14", "/usr/lib/R/bin/exec/R", "--no-echo", "-e",
      paste0("source(\"/app/R/project_ezr.R\"); ",
             "ezr_render_report(\"/app/projects/a/outputs/r\", \"/app\", 5L)"))
  expect_true(ezr_reports_running(proc))
})

# --- A report R missed on one look is still found within the tries (README "How it works") ---
test_that("a report process missing from one look is still found within the tries", {
  proc <- withr::local_tempdir()
  expect_false(ezr_reports_running(proc, tries = 3L, wait = 0.05))
  later <- sprintf("(sleep 0.3; mkdir -p %s; printf 'R\\0-e\\0ezr_render_report(1)\\0' > %s)",
                   shQuote(file.path(proc, "21")), shQuote(file.path(proc, "21", "cmdline")))
  system(later, wait = FALSE)
  expect_false(ezr_reports_running(proc, tries = 1L))
  expect_true(ezr_reports_running(proc, tries = 10L, wait = 0.1))
})

# --- The Mac start files use only messages in the list (README "Code notes") ---
test_that("the Mac launcher files use only messages that exist", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  root <- file.path("..", "..", "..")
  messages <- readLines(file.path(root, "launcher", "start_messages.txt"),
                        warn = FALSE, encoding = "UTF-8")
  keys <- sub("=.*$", "", grep("^[a-z_]+=", messages, value = TRUE))
  mac <- paste(readLines(file.path(root, "start_mac.command"), warn = FALSE), collapse = "\n")
  skip_if_not(file.exists(file.path(root, "launcher", "MacLauncher.swift")),
              "MacLauncher.swift is not here (inside the Zip)")
  swift <- paste(readLines(file.path(root, "launcher", "MacLauncher.swift"), warn = FALSE),
                 collapse = "\n")
  used_mac <- sub("^msg ", "", regmatches(mac, gregexpr("msg [a-z_]+", mac))[[1]])
  used_swift <- gsub('^T\\("|"$', "", regmatches(swift, gregexpr('T\\("[a-z_]+"', swift))[[1]])
  expect_true(length(used_mac) >= 3L)
  expect_true(length(used_swift) > 25L)
  expect_length(setdiff(c(used_mac, used_swift), keys), 0L)
  expect_false(grepl("[\u3040-\u30ff\u4e00-\u9fff]", mac))
})

# --- The Windows window script is ASCII and its messages exist (README "Code notes") ---
test_that("the Windows window script is ASCII and every message it uses exists", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  root <- file.path("..", "..", "..")
  gui <- file.path(root, "launcher", "windows_gui.ps1")
  expect_true(all(readBin(gui, "raw", n = file.info(gui)$size) < as.raw(128)))
  text <- paste(readLines(gui, warn = FALSE), collapse = "\n")
  messages <- readLines(file.path(root, "launcher", "start_messages.txt"),
                        warn = FALSE, encoding = "UTF-8")
  keys <- sub("=.*$", "", grep("^[a-z_]+=", messages, value = TRUE))
  used_gui <- unique(sub("^T '([a-z_]+)'$", "\\1",
                         regmatches(text, gregexpr("T '[a-z_]+'", text))[[1]]))
  used_gui <- c(used_gui, sub("^New-Button '([a-z_]+)'$", "\\1",
                              regmatches(text, gregexpr("New-Button '[a-z_]+'", text))[[1]]))
  expect_true(length(used_gui) > 20L)
  expect_length(setdiff(used_gui, keys), 0L)
  expect_false(anyDuplicated(keys) > 0L)
})

# --- standalone.py and both windows share words; no key waits (README "How it works") ---
test_that("standalone.py and both launcher windows share words; the worker waits for no key", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  root <- file.path("..", "..", "..")
  py <- paste(readLines(file.path(root, "launcher", "standalone.py"), warn = FALSE),
              collapse = "\n")
  gui <- paste(readLines(file.path(root, "launcher", "windows_gui.ps1"), warn = FALSE),
               collapse = "\n")
  bat <- readLines(file.path(root, "start_windows.bat"), warn = FALSE)
  mac <- readLines(file.path(root, "start_mac.command"), warn = FALSE)
  events <- c("READY", "WAIT_RECORDS", "STOP_FAILED", "BUILD_FAILED")
  for (event in events) {
    expect_true(grepl(paste0('"', event, '"'), py, fixed = TRUE), info = event)
    expect_true(grepl(paste0("'", event, "'"), gui, fixed = TRUE), info = event)
  }
  expect_true(grepl('request not in ("stop", "force-stop")', py, fixed = TRUE))
  for (action in c("stop", "force-stop")) {
    expect_true(grepl(paste0("Send-Worker '", action, "'"), gui, fixed = TRUE), info = action)
  }
  worker <- which(bat == ":worker")
  expect_length(worker, 1L)
  expect_true(grepl("--gui-worker", bat[which(grepl("^if /i", bat))[1]]))
  expect_true(any(grepl("Unblock-File", bat[seq_len(worker)])))
  after <- bat[worker:length(bat)]
  expect_false(any(grepl("^\\s*pause\\b", after)))
  expect_false(any(grepl("set /p", after, fixed = TRUE)))
  expect_true(any(grepl('standalone.py" gui-worker', after, fixed = TRUE)))
  expect_true(any(grepl("standalone.py gui-worker", mac, fixed = TRUE)))
  wait <- regmatches(py, regexpr("(?s)\\ndef wait_for_stop_requests\\(.*?\\n(?=def )", py,
                                 perl = TRUE))
  expect_true(grepl("for line in sys.stdin", wait, fixed = TRUE))
  expect_false(grepl("input(", wait, fixed = TRUE))
  skip_if_not(file.exists(file.path(root, "launcher", "MacLauncher.swift")),
              "MacLauncher.swift is not here (inside the Zip)")
  swift <- paste(readLines(file.path(root, "launcher", "MacLauncher.swift"), warn = FALSE),
                 collapse = "\n")
  for (event in events) {
    expect_true(grepl(paste0('case "', event, '"'), swift, fixed = TRUE), info = event)
  }
  for (action in c("stop", "force-stop")) {
    expect_true(grepl(paste0('send("', action, '\\n")'), swift, fixed = TRUE), info = action)
  }
})

# --- git from the env margin; only standalone.py sets the platform (README "Code notes") ---
test_that("git setting comes from the env margin; only standalone.py sets the platform", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  root <- file.path("..", "..", "..")
  env <- readLines(file.path("..", "..", "docker", "project_env.txt"), warn = FALSE)
  expect_true("GIT_DISCOVERY_ACROSS_FILESYSTEM=1" %in% env)
  mac <- readLines(file.path(root, "start_mac.command"), warn = FALSE)
  bat <- readLines(file.path(root, "start_windows.bat"), warn = FALSE)
  expect_false(any(grepl("PLATFORM|override|compose", c(mac, bat), ignore.case = TRUE)))
  py <- paste(readLines(file.path(root, "launcher", "standalone.py"), warn = FALSE),
              collapse = "\n")
  expect_true(grepl("-f docker-compose.yml -f /run/ezr-override.yml", py, fixed = TRUE))
  over <- regmatches(py, regexpr("(?s)\\ndef write_override\\(.*?\\n(?=def )", py, perl = TRUE))
  expect_true(grepl("'    platform: linux/\" + vm.arch", over, fixed = TRUE))
  expect_true(grepl("platform: linux/amd64", over, fixed = TRUE))
  expect_true(grepl("platform: linux/arm64", over, fixed = TRUE))
})

# --- standalone.py runs the stop check from R/project_ezr.R (README "Code notes") ---
test_that("both launchers run the stop check from R/project_ezr.R", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  root <- file.path("..", "..", "..")
  py <- readLines(file.path(root, "launcher", "standalone.py"), warn = FALSE)
  expect_true(any(grepl("source('R/project_ezr.R'); quit(status = ezr_records_status())", py,
                        fixed = TRUE)))
  mac <- readLines(file.path(root, "start_mac.command"), warn = FALSE)
  bat <- readLines(file.path(root, "start_windows.bat"), warn = FALSE)
  expect_true(any(grepl("./launcher/standalone.py gui-worker", mac, fixed = TRUE)))
  expect_true(any(grepl('".\\launcher\\standalone.py" gui-worker', bat, fixed = TRUE)))
})

# --- start_windows.bat does not wait itself: no timeout, ping or pause (README "Code notes") ---
test_that("start_windows.bat does not wait itself (no timeout, ping or pause)", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  bat <- readLines(file.path("..", "..", "..", "start_windows.bat"), warn = FALSE)
  expect_false(any(grepl("^\\s*(timeout|ping|pause)\\b", bat, ignore.case = TRUE, perl = TRUE)))
  expect_true(any(grepl('^start "" powershell ', bat)))
})

# --- The Windows window does not nest its reading of the worker (README "Code notes") ---
test_that("the Windows window reads the worker without running inside itself", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  gui <- readLines(file.path("..", "..", "..", "launcher", "windows_gui.ps1"), warn = FALSE)
  first <- grep("^function Receive-Output", gui)
  expect_length(first, 1L)
  body <- gui[first:(first + which(gui[-seq_len(first)] == "}")[1])]
  expect_true(any(grepl("if ($script:Receiving) { return }", body, fixed = TRUE)))
  expect_true(any(grepl("} finally {", body, fixed = TRUE)))
  handle <- grep("Receive-Line $line", body, fixed = TRUE)
  expect_length(handle, 1L)
  expect_lt(max(grep("ReadLineAsync()", body, fixed = TRUE)), handle)
})

# --- On Windows, no WSL or Hyper-V: QEMU CPU emulation (TCG) only (README "How it works") ---
test_that("on Windows the VM uses QEMU's TCG only, never WSL or Hyper-V", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  py <- readLines(file.path("..", "..", "..", "launcher", "standalone.py"), warn = FALSE)
  expect_true(any(grepl('("tcg" if self.target.startswith("windows-") else "hvf")', py,
                        fixed = TRUE)))
  expect_true(any(grepl('if self.target.startswith("windows-") and self.accelerator != "tcg":', py,
                        fixed = TRUE)))
  bat <- readLines(file.path("..", "..", "..", "start_windows.bat"), warn = FALSE)
  expect_false(any(grepl("wsl|hyper-v|whpx|docker", bat, ignore.case = TRUE)))
})

# --- Both windows copy the RStudio address with clicks only (README "If something goes wrong") ---
test_that("both launcher windows can copy the RStudio address (clicks only, no typing)", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  root <- file.path("..", "..", "..")
  skip_if_not(file.exists(file.path(root, "launcher", "MacLauncher.swift")),
              "MacLauncher.swift is not here (inside the Zip)")
  mac <- paste(readLines(file.path(root, "launcher", "MacLauncher.swift"), warn = FALSE),
               collapse = "\n")
  expect_true(grepl("copyButton, stopButton", mac, fixed = TRUE))
  expect_true(grepl("NSPasteboard.general.setString(url.absoluteString", mac, fixed = TRUE))
  gui <- paste(readLines(file.path(root, "launcher", "windows_gui.ps1"), warn = FALSE),
               collapse = "\n")
  expect_true(grepl("New-Button 'gui_copy'", gui, fixed = TRUE))
  expect_true(grepl("Clipboard]::SetText($script:Url)", gui, fixed = TRUE))
})

# --- Closing during a stop asks to wait; "already running" stays in front (README "Code notes") ---
test_that("closing during a stop asks to wait, and the already-running notice stays in front", {
  skip_if_not(file.exists(file.path("..", "..", "..", "launcher", "standalone.py")),
              "the launcher files are not visible (inside the container)")
  root <- file.path("..", "..", "..")
  gui <- paste(readLines(file.path(root, "launcher", "windows_gui.ps1"), warn = FALSE),
               collapse = "\n")
  expect_true(grepl("if ($script:CanStop -and -not $script:Requested) {", gui, fixed = TRUE))
  expect_true(grepl("$owner.TopMost = $true", gui, fixed = TRUE))
  expect_true(grepl("$owner.Opacity = 0", gui, fixed = TRUE))
  expect_lt(regexpr("$owner.Show()", gui, fixed = TRUE),
            regexpr("MessageBox]::Show($owner, (T 'gui_already')", gui, fixed = TRUE))
  expect_true(grepl("MessageBox]::Show($owner, (T 'gui_already')", gui, fixed = TRUE))
  skip_if_not(file.exists(file.path(root, "launcher", "MacLauncher.swift")),
              "MacLauncher.swift is not here (inside the Zip)")
  mac <- paste(readLines(file.path(root, "launcher", "MacLauncher.swift"), warn = FALSE),
               collapse = "\n")
  expect_true(grepl("if canStop && !requestedStop {", mac, fixed = TRUE))
})
