local_zip <- function(directory, name = "source.zip") {
  source <- tempfile(tmpdir = directory, fileext = ".txt")
  writeLines("fixture", source)
  archive <- file.path(directory, name)
  utils::zip(archive, files = source, flags = "-q")
  archive
}

test_that("source directories discover ZIP archives recursively", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "state"))
  first <- local_zip(root, "first.zip")
  second <- local_zip(file.path(root, "state"), "second.zip")

  result <- rsicar:::.sicar_source_files(root)

  expect_identical(result, sort(normalizePath(c(first, second))))
})

test_that("a source ZIP path selects only that archive", {
  root <- withr::local_tempdir()
  selected <- local_zip(root, "selected.zip")
  local_zip(root, "ignored.zip")

  result <- rsicar:::.sicar_source_files(selected)

  expect_identical(result, normalizePath(selected))
})

test_that("source validation rejects missing and non-ZIP paths", {
  root <- withr::local_tempdir()
  text_path <- file.path(root, "source.txt")
  writeLines("not an archive", text_path)

  expect_error(
    rsicar:::.sicar_source_files(file.path(root, "missing")),
    class = "rsicar_source_error"
  )
  expect_error(
    rsicar:::.sicar_source_files(text_path),
    class = "rsicar_source_error"
  )
})

test_that("source validation rejects directories without ZIP archives", {
  root <- withr::local_tempdir()
  writeLines("not an archive", file.path(root, "source.txt"))

  expect_error(
    rsicar:::.sicar_source_files(root),
    class = "rsicar_source_error"
  )
})

test_that("source validation rejects a truncated ZIP", {
  root <- withr::local_tempdir()
  archive <- file.path(root, "truncated.zip")
  writeBin(as.raw(c(0x50, 0x4b, 0x03)), archive)

  expect_error(
    rsicar:::.sicar_source_files(archive),
    class = "rsicar_source_error"
  )
})
