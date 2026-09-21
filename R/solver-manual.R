# `utils::shell.exec` only exists on Windows builds of R, so it cannot be
# referenced as `utils::shell.exec` in package source: `R CMD check` scans
# for namespace-qualified calls on every platform and would flag it as a
# missing object on macOS/Linux. Looking it up by name at call time (only
# ever reached on Windows) avoids that static check without changing
# behavior.
.sicar_windows_open <- function(path) {
  get("shell.exec", envir = asNamespace("utils"), inherits = FALSE)(path)
}

# Opens `path` with the OS default application (macOS/Linux/Windows).
# Best-effort: any failure (no GUI, missing opener binary) is swallowed,
# since the caller always has the path itself to fall back to. `sysname`,
# `windows_open`, and `system2` are overridable so the dispatch logic can be
# exercised in tests without actually launching a viewer.
.sicar_open_file <- function(
  path,
  sysname = Sys.info()[["sysname"]],
  windows_open = .sicar_windows_open,
  system2 = base::system2
) {
  opened <- tryCatch(
    suppressWarnings(
      if (identical(sysname, "Windows")) {
        windows_open(path)
        TRUE
      } else if (identical(sysname, "Darwin")) {
        identical(
          system2("open", shQuote(path), stdout = FALSE, stderr = FALSE),
          0L
        )
      } else {
        identical(
          system2("xdg-open", shQuote(path), stdout = FALSE, stderr = FALSE),
          0L
        )
      }
    ),
    error = function(error) FALSE
  )
  invisible(isTRUE(opened))
}

#' Create a manual CAPTCHA solver
#'
#' Prompts the user to type the CAPTCHA shown at the given image path. The
#' image is also opened automatically with the operating system's default
#' viewer (macOS, Linux, and Windows); if that fails (for example, a
#' headless session with no GUI), the path is still printed so the image can
#' be opened by hand. Requires an interactive session.
#'
#' @returns An object usable as the `solver` argument of `sicar_client()`.
#' @examples
#' solver <- sicar_solver_manual()
#' solver$name
#' @export
sicar_solver_manual <- function() {
  .sicar_solver(
    function(path) {
      if (!interactive()) {
        .sicar_abort(
          "The manual CAPTCHA solver requires an interactive session.",
          "rsicar_solver_error",
          path = path,
          retryable = FALSE
        )
      }
      .sicar_open_file(path)
      answer <- readline(sprintf("Enter the CAPTCHA for %s: ", path))
      .sicar_normalize_solver_output(answer)
    },
    "manual"
  )
}
