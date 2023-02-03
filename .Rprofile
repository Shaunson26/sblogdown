if (file.exists("~/.Rprofile")) {
  base::sys.source("~/.Rprofile", envir = environment())
}

# https://bookdown.org/yihui/blogdown/global-options.html
options(
  # to automatically serve the site on RStudio startup, set this option to TRUE
  blogdown.serve_site.startup = FALSE,
  blogdown.knit.on_save = FALSE,
  blogdown.author = "Shaun Nielsen",
  blogdown.ext = ".Rmarkdown",
  blogdown.subdir = "posts"
)

# fix Hugo version
options(blogdown.hugo.version = "0.110.0")

# Server settings
if (!grepl('^C', Sys.getenv('HOME'))){
  options(blogdown.hugo.dir = '/home/snielsen/.local/share/Hugo')
  Sys.setenv(HUGO_CACHEDIR = '/home/snielsen/.local/share')
}
