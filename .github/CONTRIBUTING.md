# Contributing to gitlab.nvim

Thank you for taking time to contribute to this plugin! Please follow these steps when creating a feature.

1. If the functionality you want is not a bug fix, please create a "feature request" issue first

It's possible that the feature you want is already implemented, or does not belong in `gitlab.nvim` at all. By creating an issue first you can have a conversation with the maintainers about the functionality first. While this is not strictly necessary, it greatly increases the likelihood that your merge request will be accepted.

2. Fork the repository, and create a new feature branch off the `develop` branch for your desired functionality. Make your changes.

If you are using Lazy as a plugin manager, the easiest way to work on changes is by setting a specific path for the plugin that points to your repository locally. This is what I do:

```lua
{
  "harrisoncramer/gitlab.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim",
  },
  build = function()
    require("gitlab.server").build()
  end,
  dir = "~/.path/to/your-cloned-version", -- Pass in the path to your cloned repository
  config = function()
    require("gitlab").setup({})
  end,
}
```

If you are making changes to the Go codebase, don't forget to run `make compile` in the root of the project to rebuild the binary!

3. Apply formatters and linters to your changes

For changes to the Go codebase: We use <a href="https://pkg.go.dev/cmd/gofmt">gofmt</a> to check formatting and <a href="https://github.com/golangci/golangci-lint">golangci-lint</a> to check linting, and <a href="https://staticcheck.dev/">staticcheck</a>. Run these commands in the root of the repository:

```bash
$ go fmt ./...
$ golangci-lint run ./...
$ staticcheck ./...
```

If you are writing tests and have added something to the Go client, you can test with:

```bash
$ make test
```

For changes to the Lua codebase: We use <a href="https://github.com/JohnnyMorganz/StyLua">stylua</a> for formatting and <a href="https://github.com/mpeterv/luacheck">luacheck</a> for linting. Run these commands in the root of the repository:

```bash
$ stylua .
$ luacheck --globals vim busted --no-max-line-length -- .
```

4. Make the merge request to the `develop` branch of `.gitlab.nvim`

Please provide a description of the feature, and links to any relevant issues.

That's it! I'll try to respond to any incoming merge request in a few days. Once we've reviewed it, it will be merged into the develop branch.

After some time, if the develop branch is found to be stable, that branch will be merged into `main` and released. When merged into `main` the pipeline will detect whether we're merging in a patch, minor, or major change, and create a new tag (e.g. 1.0.12) and release.
