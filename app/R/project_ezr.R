# --- Layer 4: open EZR and keep records of the work (README "How it works") ---

# --- Whether a port is listening (virtual display or noVNC is up) (README "How it works") ---
ezr_listening <- function(port) {
  connection <- tryCatch(
    suppressWarnings(socketConnection("localhost", port, open = "r+b", timeout = 1)),
    error = function(e) NULL
  )
  if (is.null(connection)) return(FALSE)
  close(connection)
  TRUE
}

# --- Add the marks against translation to a page, only once (README "How it works") ---
ezr_no_translate <- function(page) {
  html <- grep("<html", page, fixed = TRUE)[1]
  if (!is.na(html) && !grepl("translate=", page[html], fixed = TRUE)) {
    page[html] <- sub("<html", "<html translate=\"no\"", page[html], fixed = TRUE)
  }
  meta <- "<meta name=\"google\" content=\"notranslate\">"
  if (any(grepl(meta, page, fixed = TRUE))) return(page)
  head <- grep("<head>", page, fixed = TRUE)[1]
  if (is.na(head)) c(meta, page) else append(page, meta, after = head)
}

# --- Make the EZR tab's page (noVNC plus a text input box) (README "How it works") ---
ezr_web <- function(web = "/tmp/ezr-web") {
  if (dir.exists(web)) return(web)
  dir.create(web)
  file.symlink(list.files("/usr/share/novnc", full.names = TRUE), web)
  ime <- c(
    "<style>",
    "#noVNC_container { height: calc(100% - 44px); }",
    "#ezr_ime { position: fixed; left: 0; right: 0; bottom: 0; height: 44px;",
    "  display: flex; align-items: center; gap: 8px; padding: 0 8px;",
    "  box-sizing: border-box; background: #313131; }",
    "#ezr_ime label { color: #eeeeee; font-size: 14px; white-space: nowrap; }",
    "#ezr_ime input { flex: 1; font-size: 16px; padding: 4px 8px; }",
    "</style>",
    "<div id='ezr_ime'><label for='ezr_ime_text'>Text input</label>",
    "<input id='ezr_ime_text' type='text' autocomplete='off'",
    "  placeholder='Type here and press Enter to insert the text at the EZR cursor'></div>",
    "<script type='module'>",
    "import UI from './app/ui.js';",
    "const box = document.getElementById('ezr_ime_text');",
    "box.addEventListener('keydown', (event) => {",
    "  if (event.key !== 'Enter' || event.isComposing || event.keyCode === 229) return;",
    "  event.preventDefault();",
    "  if (!box.value || !UI.rfb) return;",
    "  UI.rfb.clipboardPasteFrom(box.value);",
    "  box.value = '';",
    "  setTimeout(() => {",
    "    UI.rfb.sendKey(0xffe3, 'ControlLeft', true);",
    "    UI.rfb.sendKey(0x76, 'KeyV');",
    "    UI.rfb.sendKey(0xffe3, 'ControlLeft', false);",
    "  }, 300);",
    "});",
    "</script>"
  )
  page <- ezr_no_translate(readLines("/usr/share/novnc/vnc.html", warn = FALSE))
  end <- c(grep("</body>", page, fixed = TRUE), length(page) + 1L)[1]
  writeLines(append(page, ime, after = end - 1L), file.path(web, "ezr.html"))
  writeLines(c(
    "<!doctype html><html translate=\"no\"><meta charset=\"utf-8\">",
    "<meta name=\"google\" content=\"notranslate\"><title>EZR</title><script>",
    "var base = location.pathname.replace(/[^/]*$/, \"\").replace(/^\\//, \"\");",
    "location.replace(\"ezr.html?autoconnect=true&resize=scale&path=\" + base + \"websockify\");",
    "</script>"
  ), file.path(web, "index.html"))
  web
}

# --- Whether the EZR R is running (someone reads the FIFO) (README "How it works") ---
ezr_r_alive <- function(fifo_path) {
  connection <- tryCatch(
    suppressWarnings(fifo(fifo_path, open = "w", blocking = FALSE)),
    error = function(e) NULL
  )
  if (is.null(connection)) return(FALSE)
  close(connection)
  TRUE
}

# --- Send commands to the EZR R (README "How it works") ---
ezr_send <- function(fifo_path, lines) {
  connection <- fifo(fifo_path, open = "w", blocking = TRUE)
  writeLines(lines, connection)
  close(connection)
}

# --- Start the virtual display (Xvnc), fluxbox and the noVNC relay (README "How it works") ---
ezr_display <- function() {
  if (!ezr_listening(5901L)) {
    unlink(c("/tmp/.X1-lock", "/tmp/.X11-unix/X1"))
    system2("Xvnc", c(":1", "-geometry", "1440x900", "-depth", "24",
                      "-SecurityTypes", "None", "-localhost", "-rfbport", "5901"),
            stdout = FALSE, stderr = FALSE, wait = FALSE)
    for (i in seq_len(50)) {
      if (file.exists("/tmp/.X11-unix/X1")) break
      Sys.sleep(0.1)
    }
  }
  if (system2("pgrep", c("-x", "fluxbox"), stdout = FALSE) != 0L) {
    overlay <- path.expand("~/.fluxbox/overlay")
    fonts <- c(
      "menu.frame.font: Noto Sans CJK JP-10:bold",
      "menu.title.font: Noto Sans CJK JP-12:bold",
      "toolbar.clock.font: Noto Sans CJK JP-10:bold",
      "toolbar.workspace.font: Noto Sans CJK JP-12:bold",
      "toolbar.iconbar.focused.font: Noto Sans CJK JP-10:bold",
      "toolbar.iconbar.unfocused.font: Noto Sans CJK JP-10",
      "window.font: Noto Sans CJK JP-10"
    )
    dir.create(dirname(overlay), showWarnings = FALSE)
    if (!file.exists(overlay) || !all(fonts %in% readLines(overlay, warn = FALSE))) {
      cat(fonts, file = overlay, sep = "\n", append = TRUE)
    }
    init <- path.expand("~/.fluxbox/init")
    if (!file.exists(init)) file.copy("/etc/X11/fluxbox/init", init)
    settings <- readLines(init, warn = FALSE)
    if (!"session.screen0.workspaces: 1" %in% settings) {
      settings <- settings[!grepl("^session\\.screen0\\.workspaces:", settings)]
      writeLines(c(settings, "session.screen0.workspaces: 1"), init)
    }
    keys <- path.expand("~/.fluxbox/keys")
    bindings <- c(
      "OnTitlebar Mouse1 :MacroCmd {Raise} {Focus} {ActivateTab}",
      "OnTitlebar Move1 :StartMoving",
      "OnTitlebar Double Mouse1 :Maximize",
      "OnWindowBorder Move1 :StartMoving",
      "OnLeftGrip Move1 :StartResizing bottomleft",
      "OnRightGrip Move1 :StartResizing bottomright",
      "OnWindow Mod1 Mouse1 :MacroCmd {Raise} {Focus} {StartMoving}",
      "OnWindow Mod1 Mouse3 :MacroCmd {Raise} {Focus} {StartResizing NearestCorner}"
    )
    if (!file.exists(keys) || !identical(readLines(keys, warn = FALSE), bindings)) {
      writeLines(bindings, keys)
    }
    system("DISPLAY=:1 fluxbox >/tmp/ezr-wm.log 2>&1", wait = FALSE)
  }
  if (!ezr_listening(6080L)) {
    system2("websockify", c("--web", ezr_web(), "127.0.0.1:6080", "localhost:5901"),
            stdout = FALSE, stderr = FALSE, wait = FALSE)
    Sys.sleep(1)
  }
}

# --- Record folder name (time + 4 digits from time and PID) (README "Projects and records") ---
ezr_run_dir <- function(outputs, now = Sys.time()) {
  stamp <- format(now, "%Y%m%d%H%M")
  number <- (floor(as.numeric(now) * 1000) + Sys.getpid()) %% 10000
  repeat {
    run_dir <- file.path(outputs, sprintf("%s_%04d", stamp, number))
    if (!file.exists(run_dir)) return(run_dir)
    number <- (number + 1) %% 10000
  }
}

# --- The current time, with the offset (README "Projects and records") ---
ezr_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# --- Copy the RNG kind and state, only observing (README "Projects and records") ---
ezr_rng_snapshot <- function() {
  list(
    kind = RNGkind(),
    state = if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
    } else {
      NULL
    }
  )
}

# --- Path, SHA-256, size and modified time of files (README "Projects and records") ---
ezr_describe <- function(paths, base) {
  lapply(paths, function(path) {
    list(
      path = substring(path, nchar(base) + 2),
      sha256 = digest::digest(path, algo = "sha256", file = TRUE),
      bytes = file.info(path)$size,
      modified = format(file.mtime(path), "%Y-%m-%dT%H:%M:%S%z")
    )
  })
}

# --- The files in data/ (README "Projects and records") ---
ezr_data_files <- function(project_dir) {
  sort(list.files(file.path(project_dir, "data"), recursive = TRUE, full.names = TRUE))
}

# --- data/ files the R script pane read (paths fixed by index) (README "Projects and records") ---
ezr_read_files <- function(script, project_dir) {
  if (!file.exists(script)) return(character())
  text <- paste(readLines(script, warn = FALSE), collapse = "\n")
  paths <- gsub("^\"|\"$", "", regmatches(text, gregexpr("\"[^\"\n]+\"", text))[[1]])
  relative <- !startsWith(paths, "/")
  paths[relative] <- file.path(project_dir, paths[relative])
  unique(paths[startsWith(paths, file.path(project_dir, "data", "")) & file.exists(paths)])
}

# --- Versions of R, EZR and packages, build info, renv.lock (README "Projects and records") ---
ezr_environment <- function(root) {
  spaces <- sort(loadedNamespaces())
  versions <- vapply(spaces, function(name) as.character(utils::packageVersion(name)), "")
  lock <- file.path(root, "renv.lock")
  stamp <- file.path(root, "TEMPLATE_VERSION.txt")
  build <- "/opt/build-info.json"
  list(
    r_version = R.version.string,
    platform = R.version$platform,
    locale = Sys.getlocale(),
    ezr = as.character(utils::packageVersion("RcmdrPlugin.EZR")),
    rcmdr = as.character(utils::packageVersion("Rcmdr")),
    packages = as.list(versions),
    build_info = if (file.exists(build)) jsonlite::read_json(build),
    renv_lock_sha256 = if (file.exists(lock)) digest::digest(lock, algo = "sha256", file = TRUE),
    template_version = if (file.exists(stamp)) {
      grep("^#", readLines(stamp), value = TRUE, invert = TRUE)
    }
  )
}

# --- Write meta.json (numbers unrounded; NULL and NA as null) (README "Projects and records") ---
ezr_write_meta <- function(run_dir, meta) {
  jsonlite::write_json(meta, file.path(run_dir, "meta.json"), auto_unbox = TRUE, pretty = TRUE,
                       digits = NA, null = "null", na = "null")
}

# --- Keep graphs as PNG (before a new one, every 2 s, at close) (README "Projects and records") ---
ezr_plots <- function(run_dir) {
  plot_dir <- file.path(run_dir, "plots")
  state <- new.env()
  state$count <- 0L
  state$file <- list()
  state$ops <- list()
  state$busy <- FALSE
  screens <- function() {
    devices <- grDevices::dev.list()
    devices[names(devices) %in% c("X11cairo", "X11")]
  }
  snap <- function(device) {
    current <- grDevices::dev.cur()
    state$busy <- TRUE
    on.exit({
      if (current %in% grDevices::dev.list()) grDevices::dev.set(current)
      state$busy <- FALSE
    }, add = TRUE)
    grDevices::dev.set(device)
    shown <- tryCatch(grDevices::recordPlot(), error = function(e) NULL)
    ops <- if (is.null(shown)) 0L else length(shown[[1]])
    key <- as.character(device)
    if (ops == 0L || identical(state$ops[[key]], ops)) return(invisible(FALSE))
    size <- grDevices::dev.size("px")
    temp <- tempfile(fileext = ".png")
    on.exit(unlink(temp), add = TRUE)
    grDevices::png(temp, width = size[1], height = size[2], type = "cairo")
    drawn <- tryCatch({
      grDevices::replayPlot(shown)
      TRUE
    }, error = function(e) FALSE)
    grDevices::dev.off()
    if (!drawn || !file.exists(temp)) return(invisible(FALSE))
    if (is.null(state$file[[key]])) {
      state$count <- state$count + 1L
      state$file[[key]] <- file.path(plot_dir, sprintf("plot_%03d.png", state$count))
    }
    dir.create(plot_dir, showWarnings = FALSE)
    file.copy(temp, state$file[[key]], overwrite = TRUE)
    state$ops[[key]] <- ops
    invisible(TRUE)
  }
  new_page <- function() {
    device <- grDevices::dev.cur()
    if (state$busy || !device %in% screens()) return(invisible())
    try(snap(device), silent = TRUE)
    state$file[[as.character(device)]] <- NULL
    state$ops[[as.character(device)]] <- NULL
  }
  save_all <- function() for (device in screens()) try(snap(device), silent = TRUE)
  tick <- function() {
    save_all()
    tcltk::tcl("after", 2000, tick)
  }
  grDevices::X11.options(bg = "white")
  setHook("before.plot.new", function() if (isTRUE(graphics::par("page"))) new_page())
  setHook("before.grid.newpage", new_page)
  tcltk::tcl("after", 2000, tick)
  save_all
}

# --- Wait for a process to end (a finished one left in /proc counts) (README "How it works") ---
ezr_wait_for_exit <- function(pid, timeout = 10) {
  running <- function() {
    info <- tryCatch(suppressWarnings(readLines(sprintf("/proc/%d/stat", pid), warn = FALSE)),
                     error = function(e) character())
    length(info) > 0L && !grepl("\\) [ZX] ", info[1])
  }
  for (i in seq_len(timeout * 10)) {
    if (!running()) return(TRUE)
    Sys.sleep(0.1)
  }
  !running()
}

# --- Whether an R is making a report (found by command line) (README "How it works") ---
ezr_report_seen <- function(proc = "/proc") {
  for (dir in list.files(proc, pattern = "^[0-9]+$", full.names = TRUE)) {
    bytes <- tryCatch(suppressWarnings(readBin(file.path(dir, "cmdline"), "raw", 65536L)),
                      error = function(e) raw())
    bytes[bytes == as.raw(0L)] <- as.raw(32L)
    if (grepl("ezr_render_report(", rawToChar(bytes), fixed = TRUE, useBytes = TRUE)) return(TRUE)
  }
  FALSE
}

# --- Whether an R is making a report (up to 10 looks, 0.1 s apart) (README "How it works") ---
ezr_reports_running <- function(proc = "/proc", tries = 10L, wait = 0.1) {
  for (i in seq_len(tries)) {
    if (ezr_report_seen(proc)) return(TRUE)
    if (i < tries) Sys.sleep(wait)
  }
  FALSE
}

# --- Finalize the hashes of the record files (README "Projects and records") ---
ezr_finalize_records <- function(run_dir, meta, on_stop = FALSE) {
  records <- c(file.path(run_dir, c("console.log", "script.R", "markdown.Rmd", "output.txt",
                                   "markdown.html", "markdown.log")),
               sort(list.files(file.path(run_dir, "plots"), full.names = TRUE)))
  meta$records <- ezr_describe(records[file.exists(records) & !dir.exists(records)], run_dir)
  meta$records_finalized_at <- ezr_now()
  meta$records_not_finalized <- NULL
  meta$records_finalized_on_stop <- if (isTRUE(on_stop)) TRUE
  meta
}

# --- The check before "Stop" (0: may stop, 2: not ready) (README "Projects and records") ---
ezr_records_status <- function(current = "/tmp/ezr-current", projects = "/app/projects",
                               alive = function() ezr_r_alive("/tmp/ezr-stdin"),
                               running = function() ezr_reports_running()) {
  if (!file.exists(current)) return(0L)
  value <- readLines(current, warn = FALSE)
  if (length(value) < 2L) return(2L)
  run <- normalizePath(value[[2L]], mustWork = FALSE)
  root <- paste0(normalizePath(projects, mustWork = FALSE), "/")
  if (!startsWith(run, root)) return(2L)
  if (!file.exists(file.path(run, "meta.json"))) return(2L)
  meta <- tryCatch(
    jsonlite::read_json(file.path(run, "meta.json")), error = function(e) NULL
  )
  if (is.null(meta) || !identical(meta$status, "closed")) return(2L)
  if (running()) return(2L)
  if (!is.null(meta$records_finalized_at) && is.null(meta$records_not_finalized)) return(0L)
  if (alive()) return(2L)
  report <- file.exists(file.path(run, c("markdown.html", "markdown.log")))
  meta <- ezr_finalize_records(run, meta, on_stop = TRUE)
  if (!any(report)) meta$report_missing_on_stop <- TRUE
  ezr_write_meta(run, meta)
  0L
}

# --- Rerun markdown.Rmd into markdown.html with figures (README "Projects and records") ---
ezr_render_report <- function(run_dir, project_dir, pid = NULL, wait = 10) {
  exited <- is.null(pid) || ezr_wait_for_exit(pid, wait)
  meta_path <- file.path(run_dir, "meta.json")
  meta <- if (file.exists(meta_path)) jsonlite::read_json(meta_path) else NULL
  source_lines <- readLines(file.path(run_dir, "markdown.Rmd"), warn = FALSE)
  fences <- which(source_lines == "---")
  after <- if (length(fences) >= 2 && fences[1] == 1) fences[2] else 0
  work <- tempfile("ezr-report-")
  dir.create(work)
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  fig_path <- deparse(file.path(work, "figure-html/"))
  setup <- c("", "```{r include=FALSE}",
             "knitr::opts_chunk$set(error = TRUE, dev = \"png\",",
             "                      dev.args = list(type = \"cairo\"),",
             sprintf("                      fig.path = %s)", fig_path),
             "```", "")
  input <- file.path(work, "markdown.Rmd")
  writeLines(append(source_lines, setup, after = after), input)
  suppressMessages(library(RcmdrPlugin.EZR))
  envir <- new.env(parent = globalenv())
  envir$x11 <- envir$X11 <- function(...) invisible(NULL)
  if (!is.null(meta)) meta$rng_at_report_start <- ezr_rng_snapshot()
  result <- try(rmarkdown::render(input, output_file = "markdown.html", output_dir = run_dir,
                                  intermediates_dir = work, knit_root_dir = project_dir,
                                  envir = envir, quiet = TRUE),
                silent = TRUE)
  if (inherits(result, "try-error")) {
    writeLines(as.character(result), file.path(run_dir, "markdown.log"))
  }
  if (!is.null(meta) && identical(meta$status, "closed")) {
    meta$rng_at_report_end <- ezr_rng_snapshot()
    if (exited) {
      meta <- ezr_finalize_records(run_dir, meta)
    } else {
      meta$records_finalized_at <- NULL
      meta$records_not_finalized <- sprintf(paste(
        "The EZR R had not ended after %s seconds and might still be writing console.log,",
        "so the hashes were not finalized (records are as at closing)"), wait)
    }
    ezr_write_meta(run_dir, meta)
  }
  invisible(!inherits(result, "try-error"))
}

# --- Write panes, graphs, meta.json; at close, make the report (README "Projects and records") ---
ezr_autosave <- function(run_dir, root = dirname(dirname(dirname(dirname(run_dir))))) {
  state <- environment()
  project_dir <- dirname(dirname(run_dir))
  panes <- list()
  commander <- NULL
  saved <- FALSE
  report_due <- FALSE
  reopening <- FALSE
  save_pane <- function(file) {
    try(cat(tcltk::tclvalue(tcltk::tkget(panes[[file]], "1.0", "end")),
            file = file.path(run_dir, file)), silent = TRUE)
  }
  watch <- function() {
    state$panes <- list(
      script.R = Rcmdr::LogWindow(),
      markdown.Rmd = Rcmdr::RmdWindow(),
      output.txt = Rcmdr::OutputWindow()
    )
    state$panes <- panes[vapply(panes, ezr_window_exists, logical(1))]
    for (file in names(panes)) {
      local({
        target <- file
        tcltk::tkbind(panes[[target]], "<<Modified>>", function() {
          save_pane(target)
          tcltk::tcl(panes[[target]], "edit", "modified", 0)
        })
      })
    }
    state$commander <- Rcmdr::CommanderWindow()
    tcltk::tkbind(commander, "<Destroy>", on_destroy)
  }
  save_panes <- function() {
    for (file in names(panes)) {
      save_pane(file)
      tcltk::tcl(panes[[file]], "edit", "modified", 0)
    }
  }
  start_report <- function() {
    if (!report_due || !file.exists(file.path(run_dir, "markdown.Rmd"))) return(invisible())
    state$report_due <- FALSE
    unlink(file.path(run_dir, c("markdown.html", "markdown.log")))
    command <- sprintf("source(%s); ezr_render_report(%s, %s, %dL)",
                       deparse(file.path(root, "R", "project_ezr.R")), deparse(run_dir),
                       deparse(project_dir), Sys.getpid())
    system2("Rscript", c("-e", shQuote(command)), stdout = FALSE, stderr = FALSE, wait = FALSE)
  }
  reopened <- function() {
    state$reopening <- FALSE
    if (!ezr_window_exists(Rcmdr::CommanderWindow()) ||
          identical(Rcmdr::CommanderWindow()$ID, commander$ID)) {
      return(invisible())
    }
    watch()
    for (file in names(panes)) {
      path <- file.path(run_dir, file)
      before <- if (file.exists(path)) paste(readLines(path, warn = FALSE), collapse = "\n") else ""
      now <- tcltk::tclvalue(tcltk::tkget(panes[[file]], "1.0", "end"))
      if (nzchar(trimws(before)) && !startsWith(now, before)) {
        tcltk::tkdelete(panes[[file]], "1.0", "end")
        tcltk::tkinsert(panes[[file]], "end", before)
      }
    }
    save_panes()
    state$meta$status <- "open"
    state$meta["closed"] <- list(NULL)
    state$meta[c("data_at_close", "read_files", "records", "rng_at_close")] <- NULL
    try(ezr_write_meta(run_dir, meta), silent = TRUE)
    state$saved <- FALSE
    state$report_due <- FALSE
  }
  suppressMessages(trace("Commander", where = asNamespace("Rcmdr"), print = FALSE,
                         tracer = function() state$reopening <- TRUE, exit = function() reopened()))
  reg.finalizer(environment(), function(e) start_report(), onexit = TRUE)
  save_plots <- ezr_plots(run_dir)
  meta <- list(
    project = basename(project_dir), run = basename(run_dir), status = "open",
    opened = ezr_now(), closed = NULL, environment = ezr_environment(root),
    rng_at_open = ezr_rng_snapshot(),
    data_at_open = ezr_describe(ezr_data_files(project_dir), project_dir)
  )
  try(ezr_write_meta(run_dir, meta), silent = TRUE)
  on_destroy <- function(W) {
    window <- as.character(W)
    if (!identical(window, commander$ID) && !startsWith(window, paste0(commander$ID, "."))) return()
    if (!saved) {
      state$meta$rng_at_close <- ezr_rng_snapshot()
      for (file in names(panes)) save_pane(file)
      save_plots()
      try({
        state$meta$status <- "closed"
        state$meta$closed <- ezr_now()
        state$meta$environment$packages <- ezr_environment(root)$packages
        state$meta$data_at_close <- ezr_describe(ezr_data_files(project_dir), project_dir)
        read <- ezr_read_files(file.path(run_dir, "script.R"), project_dir)
        state$meta$read_files <- ezr_describe(read, project_dir)
        records <- c(file.path(run_dir, names(panes)),
                     sort(list.files(file.path(run_dir, "plots"), full.names = TRUE)))
        state$meta$records <- ezr_describe(records[file.exists(records)], run_dir)
        ezr_write_meta(run_dir, meta)
      }, silent = TRUE)
      state$saved <- TRUE
      state$report_due <- TRUE
    }
    if (identical(window, commander$ID)) {
      tcltk::tcl("after", 1000, function() {
        if (reopening || ezr_window_exists(Rcmdr::CommanderWindow())) return(invisible())
        start_report()
        quit(save = "no")
      })
    }
  }
  watch()
  save_panes()
  invisible(run_dir)
}

# --- Whether a Tk window still exists (README "Projects and records") ---
ezr_window_exists <- function(window) {
  !is.null(window) &&
    identical(tcltk::tclvalue(tcltk::tkwinfo("exists", window)), "1")
}

# --- The notice for what EZR tried to open in a browser (README "How it works") ---
ezr_browser_text <- function(url, root) {
  path <- sub("^file://(localhost)?/*", "/", url)
  if (startsWith(path, paste0(root, "/")) && file.exists(path)) {
    return(paste0("Files cannot be opened from the EZR screen. ",
                  "Open this file in RStudio's Files pane.\n\n",
                  substring(path, nchar(root) + 2L)))
  }
  if (grepl("^https?://", url) && !grepl("^https?://(localhost|127\\.0\\.0\\.1)[:/]", url)) {
    return(paste0("A browser cannot be opened from the EZR screen. ",
                  "Open this URL in your own browser.\n\n", url))
  }
  if (startsWith(path, "/")) {
    return(paste0("This file (", basename(path), ") cannot be opened from the EZR screen."))
  }
  "Help cannot be opened from the EZR screen. Look up R help in RStudio's Help pane."
}

# --- Show a notice instead of opening a browser from EZR (README "How it works") ---
ezr_browser <- function(url, root) {
  tcltk::tkmessageBox(title = "EZR", message = ezr_browser_text(url, root),
                      icon = "info", type = "ok")
  invisible(url)
}

# --- Whether a project name is usable (letters, digits, _ . -) (README "How it works") ---
ezr_valid_name <- function(project) {
  is.character(project) && length(project) == 1L && grepl("^[A-Za-z0-9][A-Za-z0-9_.-]*$", project)
}

# --- Projects directly under projects/, by last use (README "How it works") ---
ezr_projects <- function(root = getwd()) {
  dirs <- list.dirs(file.path(root, "projects"), full.names = TRUE, recursive = FALSE)
  dirs <- dirs[vapply(basename(dirs), ezr_valid_name, logical(1))]
  used <- file.mtime(file.path(dirs, "outputs"))
  used[is.na(used)] <- file.mtime(dirs[is.na(used)])
  projects <- data.frame(name = basename(dirs), last_used = used)[order(used, decreasing = TRUE), ]
  rownames(projects) <- NULL
  projects
}

# --- The project folder (creates data/ and outputs/) (README "Projects and records") ---
ezr_project_dir <- function(project, root = getwd()) {
  project_dir <- file.path(root, "projects", project)
  for (part in c("data", "outputs")) {
    dir.create(file.path(project_dir, part), recursive = TRUE, showWarnings = FALSE)
  }
  project_dir
}

# --- Data formats and size that can be added (README "Projects and records") ---
ezr_data_types <- c("csv", "xlsx", "xls")
ezr_data_max <- 15 * 1024^2

# --- Return the files that cannot be added, with the reason (README "Projects and records") ---
ezr_check_data <- function(files) {
  type <- tolower(tools::file_ext(files$name))
  why <- ifelse(!type %in% ezr_data_types, "not CSV or Excel",
                ifelse(files$size > ezr_data_max, "larger than 15 MB", NA))
  sprintf("%s (%s)", files$name, why)[!is.na(why)]
}

# --- Copy data into data/ (no overwrite, same content skipped) (README "Projects and records") ---
ezr_add_data <- function(files, data_dir) {
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
  notes <- character()
  for (i in seq_len(nrow(files))) {
    name <- basename(files$name[i])
    stem <- tools::file_path_sans_ext(name)
    new_sum <- unname(tools::md5sum(files$datapath[i]))
    same <- FALSE
    for (k in seq_len(1000)) {
      target <- if (k == 1) name else sprintf("%s_%d.%s", stem, k, tools::file_ext(name))
      path <- file.path(data_dir, target)
      if (!file.exists(path)) break
      same <- identical(unname(tools::md5sum(path)), new_sum)
      if (same) break
    }
    if (same) {
      notes <- c(notes, sprintf("%s with the same content already exists, so it was not added",
                                target))
      next
    }
    if (!file.copy(files$datapath[i], path)) stop("Could not copy to data: ", name)
    notes <- c(notes, if (identical(target, name)) {
      sprintf("Added %s", name)
    } else {
      sprintf("%s already exists, so it was added as %s", name, target)
    })
  }
  notes
}

# --- Default name of a new project (never clashes) (README "How it works") ---
ezr_default_name <- function(root, now = Sys.time()) {
  base <- paste0("study_", format(now, "%Y%m%d_%H%M%S"))
  name <- base
  suffix <- 1L
  while (file.exists(file.path(root, "projects", name))) {
    name <- paste0(base, "_", suffix)
    suffix <- suffix + 1L
  }
  name
}

# --- Checks of the "Open EZR" window; returns the choice (README "How it works") ---
ezr_start_server <- function(root, new = ".new", stop_app = shiny::stopApp) {
  function(input, output, session) {
    closed <- FALSE
    problem <- shiny::reactiveVal("")
    data_problem <- shiny::reactiveVal("")
    output$problem <- shiny::renderText(problem())
    output$data_problem <- shiny::renderText(data_problem())
    show <- function(id) session$sendCustomMessage("ezr_show", id)
    shiny::observeEvent(input$data, {
      bad <- ezr_check_data(input$data)
      data_problem(if (length(bad) == 0) "" else paste0(
        "Some files cannot be added. Use CSV or Excel files of up to 15 MB each, ",
        "and add them again: ", paste(bad, collapse = ", ")
      ))
      if (length(bad) > 0) show("data_problem")
      session$sendCustomMessage("ezr_data", list(
        text = paste(input$data$name, collapse = ", "),
        bar = if (length(bad) == 0) "Received" else "Some files cannot be added"
      ))
    })
    shiny::observeEvent(input$done, {
      if (nzchar(data_problem())) {
        show("data_problem")
        return()
      }
      if (ezr_reports_running()) {
        problem(paste0("The report of the previous session (markdown.html) is being made. ",
                       "Wait a little, then press \"Open EZR\" again."))
        show("problem")
        return()
      }
      project <- input$pick
      if (identical(project, new)) {
        project <- trimws(input$name)
        if (!ezr_valid_name(project)) {
          problem(paste0("Start the name with a letter or digit, ",
                         "and use only letters, digits, _ . -. e.g. studyA"))
          show("problem")
          return()
        }
        if (dir.exists(file.path(root, "projects", project))) {
          problem(sprintf("\"%s\" already exists. Choose it from the list.", project))
          show("problem")
          return()
        }
      }
      notes <- character()
      if (!is.null(input$data)) {
        notes <- ezr_add_data(input$data, file.path(ezr_project_dir(project, root), "data"))
      }
      closed <<- TRUE
      stop_app(list(project = project, notes = notes))
    })
    shiny::observeEvent(input$cancel, {
      closed <<- TRUE
      stop_app(NULL)
    })
    shiny::observeEvent(list(input$pick, input$name), problem(""), ignoreInit = TRUE)
    session$onSessionEnded(function() if (!closed) stop_app(list(lost = TRUE)))
  }
}

# --- The "Open EZR" window (README "How it works") ---
ezr_start <- function(root = getwd()) {
  if (!rstudioapi::isAvailable()) {
    stop("Use this inside RStudio (outside RStudio, call ezr_open(\"<name>\"))")
  }
  root <- normalizePath(root)
  projects <- ezr_projects(root)
  labels <- sprintf("%s (last used %s)", projects$name, format(projects$last_used, "%Y-%m-%d"))
  new <- ".new"
  default_name <- ezr_default_name(root)
  suppressPackageStartupMessages(loadNamespace("miniUI"))
  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar(
      "Open EZR",
      left = miniUI::miniTitleBarCancelButton(label = "Cancel"),
      right = miniUI::miniTitleBarButton("done", "Open EZR", primary = TRUE)
    ),
    miniUI::miniContentPanel(
      shiny::radioButtons("pick", "Choose a project",
                          choiceNames = c(labels, "+ Create a new project"),
                          choiceValues = c(projects$name, new),
                          selected = c(projects$name, new)[1]),
      shiny::conditionalPanel(
        sprintf("input.pick == '%s'", new),
        shiny::textInput("name", "Name of the new project (letters, digits, _ . -)",
                         value = default_name, placeholder = "e.g. studyA")),
      shiny::div(style = "color: #c0392b; font-weight: bold;", shiny::textOutput("problem")),
      shiny::fileInput("data",
                       "Add data (CSV or Excel, up to 15 MB each. You can also add data later)",
                       multiple = TRUE, accept = paste0(".", ezr_data_types), width = "100%",
                       buttonLabel = "Browse...", placeholder = "Choose files with Browse..."),
      shiny::div(style = "color: #c0392b; font-weight: bold;", shiny::textOutput("data_problem")),
      shiny::tags$script(shiny::HTML(paste(
        "Shiny.addCustomMessageHandler('ezr_data', function(x) {",
        "  $('#data').closest('.input-group').find('input[type=text]').val(x.text);",
        "  $('#data_progress .progress-bar').text(x.bar);",
        "});",
        "Shiny.addCustomMessageHandler('ezr_show', function(id) {",
        "  setTimeout(function() {",
        "    var box = document.getElementById(id);",
        "    if (box) box.parentNode.scrollIntoView({block: 'nearest'});",
        "  }, 100);",
        "});"
      )))
    )
  )
  server <- ezr_start_server(root, new)
  old <- options(shiny.maxRequestSize = 1024^3)
  on.exit(options(old), add = TRUE)
  viewer <- shiny::dialogViewer("Open EZR", width = 560, height = 600)
  for (shown in seq_len(10)) {
    result <- suppressMessages(shiny::runGadget(ui, server, stopOnCancel = FALSE, viewer = viewer))
    interrupted <- FALSE
    for (i in seq_len(40)) {
      interrupted <- isTRUE(tryCatch({
        Sys.sleep(0.05)
        FALSE
      }, interrupt = function(e) TRUE))
      if (interrupted) break
    }
    if (!isTRUE(result$lost) || interrupted) break
  }
  if (is.null(result) || isTRUE(result$lost)) {
    message("Cancelled opening EZR")
    return(invisible(NULL))
  }
  for (note in result$notes) message("Data: ", note)
  project <- result$project
  later::later(function() {
    tryCatch(ezr_open(project, root), error = function(e) {
      rstudioapi::sendToConsole(sprintf("stop(%s, call. = FALSE)", deparse1(conditionMessage(e))),
                                execute = TRUE, echo = FALSE, focus = FALSE)
    })
  })
  invisible(NULL)
}

# --- When RStudio opens, send ezr_start.R to the console once (README "How it works") ---
ezr_autostart <- function(root = getwd(), flag = "/tmp/ezr-autostart") {
  launcher <- file.path(root, "ezr_start.R")
  if (file.exists(flag) || !file.exists(launcher)) return(invisible(FALSE))
  file.create(flag)
  rstudioapi::sendToConsole(sprintf("source(%s)", deparse(launcher)),
                            execute = TRUE, echo = FALSE, focus = FALSE)
  invisible(TRUE)
}

# --- Open EZR (close the previous one, make the record folder) (README "How it works") ---
ezr_open <- function(project, root = getwd()) {
  if (missing(project) || !ezr_valid_name(project)) {
    stop("Pass the project name in letters and digits (and _ . -). e.g. ezr_open(\"studyA\")")
  }
  root <- normalizePath(root)
  fifo_path <- "/tmp/ezr-stdin"
  current_file <- "/tmp/ezr-current"
  ezr_display()
  if (ezr_r_alive(fifo_path)) {
    current <- if (file.exists(current_file)) readLines(current_file, n = 1L) else ""
    if (identical(current, project)) {
      utils::browseURL("http://localhost:6080/")
      return(invisible(NULL))
    }
    if (nzchar(current)) {
      message("Closing the previous EZR (", current, ")...")
      ezr_send(fifo_path, "Rcmdr::closeCommander(ask = FALSE)")
      for (i in seq_len(200)) {
        if (!ezr_r_alive(fifo_path)) break
        Sys.sleep(0.1)
      }
    } else {
      message("Closing an EZR that stopped partway...")
    }
    if (ezr_r_alive(fifo_path)) ezr_send(fifo_path, "quit(save = \"no\")")
    for (i in seq_len(50)) {
      if (!ezr_r_alive(fifo_path)) break
      Sys.sleep(0.1)
    }
    if (ezr_r_alive(fifo_path)) {
      stop("The previous EZR (", current, ") has not closed yet. In the EZR tab, close any open ",
           "window (such as a file chooser or a question), or wait for the computation to end, ",
           "and the previous EZR closes. Then open ezr_start.R, press \"Source\", and choose ",
           "again.",
           call. = FALSE)
    }
  }
  if (ezr_reports_running()) {
    message("The report of the previous session is being made. \"", project,
            "\" opens when it is done…")
    while (ezr_reports_running()) Sys.sleep(0.5)
  }
  project_dir <- ezr_project_dir(project, root)
  run_dir <- ezr_run_dir(file.path(project_dir, "outputs"))
  dir.create(run_dir, recursive = TRUE)
  writeLines(c("", run_dir), current_file)
  rstudio_vars <- grep("^(RSTUDIO|RS_)", names(Sys.getenv()), value = TRUE)
  system(paste(
    "cd", shQuote(project_dir), "&&",
    "env", paste0("-u ", rstudio_vars, collapse = " "), "DISPLAY=:1",
    "R --interactive --no-save --no-restore --quiet",
    paste0("0<>", fifo_path), ">", shQuote(file.path(run_dir, "console.log")), "2>&1"
  ), wait = FALSE)
  for (i in seq_len(100)) {
    if (ezr_r_alive(fifo_path)) break
    Sys.sleep(0.1)
  }
  if (!ezr_r_alive(fifo_path)) {
    stop("The R process that opens EZR did not start (see ", file.path(run_dir, "console.log"), ")")
  }
  ezr_send(fifo_path, c(
    "invisible(Sys.setlocale(\"LC_MESSAGES\", \"en_US.UTF-8\"))",
    "invisible(Sys.setLanguage(\"en\"))",
    sprintf("source(%s)", deparse(file.path(root, "R", "project_ezr.R"))),
    sprintf("options(browser = function(url) ezr_browser(url, %s))", deparse(root)),
    "options(Rcmdr = list(plugins = \"RcmdrPlugin.EZR\"))",
    "library(Rcmdr)",
    sprintf("ezr_autosave(%s, %s)", deparse(run_dir), deparse(root))
  ))
  writeLines(c(project, run_dir), current_file)
  utils::browseURL("http://localhost:6080/")
  message("Record folder: ", run_dir)
  invisible(run_dir)
}
