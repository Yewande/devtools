#' Build package.
#'
#' Building converts a package source directory into a single bundled file.
#' If \code{binary = FALSE} this creates a \code{tar.gz} package that can
#' be installed on any platform, provided they have a full development
#' environment (although packages without source code can typically be
#' install out of the box). If \code{binary = TRUE}, the package will have
#' a platform specific extension (e.g. \code{.zip} for windows), and will
#' only be installable on the current platform, but no development
#' environment is needed.
#'
#' @param pkg package description, can be path or package name.  See
#'   \code{\link{as.package}} for more information
#' @param path path in which to produce package.  If \code{NULL}, defaults to
#'   the parent directory of the package.
#' @param binary Produce a binary (\code{--binary}) or source (
#'   \code{--no-manual --no-resave-data}) version of the package.
#' @param vignettes,manual For source packages: if \code{FALSE}, don't build PDF
#'   vignettes (\code{--no-build-vignettes}) or manual (\code{--no-manual}).
#' @param args An optional character vector of additional command
#'   line arguments to be passed to \code{R CMD build} if \code{binary = FALSE},
#'   or \code{R CMD install} if \code{binary = TRUE}.
#' @param quiet if \code{TRUE} suppresses output from this function.
#' @export
#' @family build functions
#' @return a string giving the location (including file name) of the built
#'  package
build <- function(pkg = ".", path = NULL, binary = FALSE, vignettes = TRUE,
                  manual = FALSE, args = NULL, quiet = FALSE) {
  pkg <- as.package(pkg)
  if (is.null(path)) {
    path <- dirname(pkg$path)
  }

  check_build_tools(pkg)
  compile_rcpp_attributes(pkg)

  if (binary) {
    args <- c("--build", args)
    cmd <- paste0("CMD INSTALL ", shQuote(pkg$path), " ",
      paste0(args, collapse = " "))
    if (.Platform$OS.type == "windows") {
      ext <- ".zip"
    } else if (grepl("darwin", R.version$os)) {
      ext <- ".tgz"
    } else {
      ext <- paste0("_R_", Sys.getenv("R_PLATFORM"), ".tar.gz")
    }
  } else {
    args <- c(args, "--no-resave-data")

    if (manual && !has_latex()) {
      message("pdflatex not found! Not building PDF manual or vignettes.\n",
        "If you are planning to release this package, please run a check with ",
        "manual and vignettes beforehand.\n")
      manual <- FALSE
    }

    if (!manual) {
      args <- c(args, "--no-manual")
    }

    if (!vignettes) {
      args <- c(args, "--no-build-vignettes")
    }

    cmd <- paste0("CMD build ", shQuote(pkg$path), " ",
      paste0(args, collapse = " "))

    ext <- ".tar.gz"
  }

  # Create temporary library to ensure that default library doesn't get
  # contaminated
  temp_lib <- tempfile()
  dir.create(temp_lib)
  on.exit(unlink(temp_lib, recursive = TRUE), add = TRUE)

  withr::with_libpaths(c(temp_lib, .libPaths()), R(cmd, path, quiet = quiet))
  targz <- paste0(pkg$package, "_", pkg$version, ext)

  file.path(path, targz)
}


#' Build windows binary package.
#'
#' This function works by bundling source package, and then uploading to
#' \url{http://win-builder.r-project.org/}.  Once building is complete you'll
#' receive a link to the built package in the email address listed in the
#' maintainer field.  It usually takes around 30 minutes. As a side effect,
#' win-build also runs \code{R CMD check} on the package, so \code{build_win}
#' is also useful to check that your package is ok on windows.
#'
#' @param pkg package description, can be path or package name.  See
#'   \code{\link{as.package}} for more information
#' @inheritParams build
#' @param version directory to upload to on the win-builder, controlling
#'   which version of R is used to build the package. Possible options are
#'   listed on \url{http://win-builder.r-project.org/}. Defaults to R-devel.
#' @export
#' @family build functions
build_win <- function(pkg = ".", version = c("R-release", "R-devel"),
                      args = NULL, quiet = FALSE) {
  pkg <- as.package(pkg)

  if (missing(version)) {
    version <- "R-devel"
  } else {
    version <- match.arg(version, several.ok = TRUE)
  }

  if (!quiet) {
    message("Building windows version of ", pkg$package,
            " for ", paste(version, collapse=", "),
            " with win-builder.r-project.org.\n")
    if (interactive() && yesno("E-mail will be delivered to ", maintainer(pkg)$email, ".")) {
      return(invisible())
    }
  }

  built_path <- build(pkg, tempdir(), args = args, quiet = quiet)
  on.exit(unlink(built_path))

  url <- paste0("ftp://win-builder.r-project.org/", version, "/",
                basename(built_path))
  lapply(url, upload_ftp, file = built_path)

  if (!quiet) {
    message("Check ", maintainer(pkg)$email, " for a link to the built package",
            if (length(version) > 1) "s" else "",
            " in 30-60 mins.")
  }

  invisible()
}
