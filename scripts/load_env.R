# Source from other scripts: loads project .env when present.
if (file.exists(".env")) {
  readRenviron(".env")
} else if (file.exists(file.path("..", ".env"))) {
  readRenviron(file.path("..", ".env"))
}
